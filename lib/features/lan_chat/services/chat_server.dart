import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import 'lan_chat_settings.dart';

/// 帧类型标记
const int kJsonMarker = 0x4A; // 'J'
const int kFileChunkV2Marker = 0x47; // 'G' 文件数据块(自带 transferId,支持同连接并发多文件)

/// 单次 socket 数据事件内最多同步解析的帧数。
/// 大文件接收时数据连续到达,若一次性解析完缓冲里所有帧,
/// 主 isolate 会被持续占满,接收端 UI 事件永远得不到执行 → 卡死;
/// 超过该帧数后让出事件循环(Timer.run),分批继续解析。
/// E方案: 32 → 16,单批处理量减半,让出事件循环更频繁,
/// 配合 512KB 发送块,每批约 8MB,主 isolate 单次占用时间更短。
const int kMaxFramesPerBatch = 16;

/// 发送端每积累多少块才 flush 一次(替代逐块 flush):
/// 减少系统调用次数,吞吐提升;接收端已有背压(pause/resume),
/// 发送速率仍由 TCP 窗口与接收端消费自然节流。
const int kChunksPerFlush = 16;

/// 增量 MD5 计算器(crypto 3.x 移除 Md5 类,改用 startChunkedConversion)
/// 发送/接收侧共用:逐块 add,结束时 close 返回十六进制 MD5。
class Md5Accumulator {
  final _DigestSink _inner = _DigestSink();
  late final ByteConversionSink _sink;

  Md5Accumulator() {
    _sink = md5.startChunkedConversion(_inner);
  }

  /// 追加字节(发送/落盘时随数据调用)
  void add(List<int> bytes) => _sink.add(bytes);

  /// 结束计算并返回十六进制 MD5
  String close() {
    _sink.close();
    return _inner.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// TCP 消息接收回调
typedef OnMessageReceived = void Function(ChatMessage message);
/// TCP 文件元信息接收回调（peerId 为对方的设备 ID）
typedef OnFileMetaReceived = void Function(
    String transferId, String fileName, int fileSize, String peerId);
/// TCP 文件数据块接收回调
typedef OnFileChunkReceived = void Function(String transferId, List<int> chunk);
/// TCP 文件传输完成回调(md5 为发送方计算的校验值,旧版本可能为空)
typedef OnFileDoneReceived = void Function(String transferId, String? md5);
/// TCP 文件传输错误回调(发送方出错时通知接收方,接收方应标记失败而非完成)
typedef OnFileErrorReceived = void Function(String transferId, String error);
/// TCP 文件控制消息回调(pause/resume/cancel)
typedef OnFileControlReceived = void Function(String transferId, String action);
/// 文件接收就绪回调(file_ready 到达,发送方据此开始推数据)
typedef OnFileReadyReceived = void Function(String transferId);
/// TCP 日志回调
typedef OnLog = void Function(String log);
/// 新 peer 连接回调（ip/tcpPort 来自对方握手消息）
typedef OnPeerConnected = void Function(String peerId, String ip, int tcpPort);
/// peer 断开回调
typedef OnPeerDisconnected = void Function(String peerId);

/// 已连接的 peer 信息
class _PeerInfo {
  final Socket socket;
  final String ip;
  StreamSubscription<Uint8List>? sub; // socket 数据订阅(背压 pause/resume 用)
  String? peerId;
  int tcpPort = 0;
  int msgLen = -1; // 当前帧数据长度，跨 TCP 包保持
  int? frameType; // 当前帧类型（kJsonMarker/kFileChunkV2Marker）

  _PeerInfo({required this.socket, required this.ip});
}

/// 本地 TCP 服务器
/// 监听端口，接收其他设备发来的消息和文件，并支持双向通信
class ChatServer {
  ServerSocket? _serverSocket;
  bool _isRunning = false;
  final Map<String, _PeerInfo> _connectedPeers = {}; // peerId -> peer info
  final List<_PeerInfo> _pendingPeers = []; // 尚未识别 peerId 的连接

  OnMessageReceived? onMessage;
  OnFileMetaReceived? onFileMeta;
  OnFileChunkReceived? onFileChunk;
  OnFileDoneReceived? onFileDone;
  OnFileErrorReceived? onFileError;
  OnFileControlReceived? onFileControl;
  OnPeerConnected? onPeerConnected;
  OnPeerDisconnected? onPeerDisconnected;
  OnLog? onLog;

  /// 等待对方 file_ready 的 completer(按 transferId)
  final Map<String, Completer<void>> _fileReadyCompleters = {};

  int get port => _serverSocket?.port ?? 0;
  bool get isRunning => _isRunning;

  /// 获取所有已连接的 peer ID
  List<String> get connectedPeerIds => _connectedPeers.keys.toList();

  /// 检查某 peer 是否已连接我们的服务器
  bool isPeerConnected(String peerId) => _connectedPeers.containsKey(peerId);

  /// 候选端口数量:默认端口被占用时,依次尝试后续连续端口,尽量保持端口可预期
  static const int _portCandidateCount = 20;

  /// 启动 TCP 服务器
  ///
  /// 优先尝试 [port] 起的连续候选端口,全部被占用时才回退到系统随机空闲端口,
  /// 避免端口冲突时聊天端口完全不可预期(真实端口会随心跳广播给对方)。
  Future<int> start({int port = LanChatSettings.defaultChatPort}) async {
    if (_isRunning) return port;

    for (var candidate = port; candidate < port + _portCandidateCount; candidate++) {
      try {
        return await _bindAndListen(candidate);
      } catch (e) {
        debugPrint('[ChatServer] Bind port $candidate failed: $e');
      }
    }

    // 候选端口全部被占用,回退到系统随机空闲端口
    debugPrint(
        '[ChatServer] Ports $port-${port + _portCandidateCount - 1} all occupied, fallback to random port');
    return _bindAndListen(0);
  }

  Future<int> _bindAndListen(int port) async {
    _serverSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
    );
    _isRunning = true;

    _serverSocket!.listen(
      _handleClient,
      onError: (error) {
        debugPrint('[ChatServer] Error: $error');
      },
    );

    debugPrint('[ChatServer] Listening on port ${_serverSocket!.port}');
    return _serverSocket!.port;
  }

  /// 停止服务器
  void stop() {
    _isRunning = false;
    for (final peer in _connectedPeers.values) {
      peer.socket.close();
    }
    _connectedPeers.clear();
    for (final peer in _pendingPeers) {
      peer.socket.close();
    }
    _pendingPeers.clear();
    _serverSocket?.close();
    _serverSocket = null;
    debugPrint('[ChatServer] Stopped');
  }

  /// 向已连接的 peer 发送消息，成功返回 true（连接失效返回 false）
  bool sendMessage(String peerId, ChatMessage msg) {
    final peer = _connectedPeers[peerId];
    if (peer == null) {
      debugPrint('[ChatServer] sendMessage FAILED: $peerId not connected');
      return false;
    }
    debugPrint(
        '[ChatServer] sendMessage to $peerId: type=${msg.type.name} content=${msg.content}');
    return _sendJson(peer.socket, msg.toJson());
  }

  /// 向已连接的 peer 发送文件控制消息(pause/resume/cancel)
  bool sendFileControl(String peerId, String transferId, String action) {
    final peer = _connectedPeers[peerId];
    if (peer == null) {
      debugPrint('[ChatServer] sendFileControl FAILED: $peerId not connected');
      return false;
    }
    debugPrint('[ChatServer] sendFileControl to $peerId: $action transfer=$transferId');
    return _sendJson(peer.socket, {'type': 'file_$action', 'id': transferId});
  }

  /// 向已连接的 peer 发送 JSON 数据（'J' 标记 + TLV 格式），成功返回 true
  bool _sendJson(Socket socket, Map<String, dynamic> json) {
    try {
      final data = utf8.encode(jsonEncode(json));
      final header = <int>[
        kJsonMarker,
        (data.length >> 24) & 0xFF,
        (data.length >> 16) & 0xFF,
        (data.length >> 8) & 0xFF,
        data.length & 0xFF,
      ];
      socket.add(header);
      socket.add(data);
      socket.flush();
      return true;
    } catch (e, st) {
      debugPrint('[ChatServer] Send error: $e\n$st');
      return false;
    }
  }

  /// 仅当该 peer 仍映射到本连接时才移除，
  /// 避免旧连接的 onDone/onError 误删新建立的同 peer 连接
  void _removePeerIfCurrent(_PeerInfo peerInfo) {
    final id = peerInfo.peerId;
    if (id != null && identical(_connectedPeers[id], peerInfo)) {
      _connectedPeers.remove(id);
      onPeerDisconnected?.call(id);
    }
  }

  /// 通过已连接的 peer socket 发送文件（服务端通道）
  /// 先发元信息，再发文件内容，格式与 ChatClient.sendFile 一致。
  /// 统一使用自带 transferId 的 'G' 帧(同连接并发多文件不串线),
  /// 原始字节直传(无压缩、无断点续传);发送过程增量计算 MD5,随 file_done 一并发出。
  /// [filePath] 可为空(流式源场景);[readStream] 提供按块读取的流,
  /// 有流时直接消费流,否则从文件路径读取。
  /// [isCancelled] 每块发送前检查,返回 true 时中止发送。
  Stream<double> sendFile({
    required String peerId,
    required String transferId,
    String? filePath,
    required String fileName,
    required int fileSize,
    Stream<List<int>>? readStream,
    bool Function()? isCancelled,
  }) async* {
    final peer = _connectedPeers[peerId];
    if (peer == null) {
      debugPrint('[ChatServer] Cannot send file to $peerId: not connected');
      return;
    }
    final socket = peer.socket;

    // 用户可能在重连/等待期间点了取消:取消后不再发 meta、不再推数据
    if (isCancelled?.call() ?? false) {
      debugPrint('[ChatServer] File send cancelled before meta: $fileName');
      return;
    }

    // 发送文件元信息(原始字节直传,无压缩、无断点续传)
    _sendJson(socket, {
      'type': 'file_meta',
      'id': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
    });

    // 等待对方接收就绪;对端不回时超时兜底后继续
    await _waitForReady(transferId, isCancelled: isCancelled);

    // 发送文件内容
    try {
      final totalBytes =
          readStream != null ? fileSize : await File(filePath ?? '').length();
      var sentBytes = 0;
      // 发送侧统一逐块增量累加 MD5,不再在发送完成后重读整个文件计算
      final md5Acc = Md5Accumulator();

      // 发送一块数据:帧封装 + MD5 + 进度;返回 null 表示已取消
      // 每 kChunksPerFlush 块 flush 一次,减少系统调用
      var chunksSinceFlush = 0;
      Future<double?> sendChunk(List<int> chunk) async {
        // 取消检查:中止且不发完成标记
        if (isCancelled?.call() ?? false) {
          debugPrint('[ChatServer] File send cancelled: $fileName');
          return null;
        }
        if (chunk.isEmpty) {
          return totalBytes > 0 ? sentBytes / totalBytes : 0.0;
        }

        // 'G' 帧:4字节内容长度 + [tidLen(4) + transferId + 数据]
        final tidBytes = utf8.encode(transferId);
        final contentLen = 4 + tidBytes.length + chunk.length;
        socket.add(<int>[
          kFileChunkV2Marker,
          (contentLen >> 24) & 0xFF,
          (contentLen >> 16) & 0xFF,
          (contentLen >> 8) & 0xFF,
          contentLen & 0xFF,
          (tidBytes.length >> 24) & 0xFF,
          (tidBytes.length >> 16) & 0xFF,
          (tidBytes.length >> 8) & 0xFF,
          tidBytes.length & 0xFF,
        ]);
        socket.add(tidBytes);
        socket.add(chunk);
        chunksSinceFlush++;
        if (chunksSinceFlush >= kChunksPerFlush) {
          await socket.flush();
          chunksSinceFlush = 0;
        }

        sentBytes += chunk.length;
        return totalBytes > 0 ? sentBytes / totalBytes : 0.0;
      }

      if (readStream != null) {
        // 流式源:直接逐块消费
        await for (final chunk in readStream) {
          md5Acc.add(chunk);
          final p = await sendChunk(chunk);
          if (p == null) return;
          yield p;
        }
      } else {
        // 文件路径:RandomAccessFile 按 512KB 大块读取
        final raf = await File(filePath ?? '').open();
        try {
          var remaining = totalBytes;
          // 512KB 单帧 + kMaxFramesPerBatch=16 每批约 8MB,
          // 接收端主 isolate 单次占用更短,UI 更流畅
          const chunkSize = 512 * 1024;
          while (remaining > 0) {
            final readLen = remaining < chunkSize ? remaining : chunkSize;
            final chunk = await raf.read(readLen);
            if (chunk.isEmpty) break;
            md5Acc.add(chunk);
            final p = await sendChunk(chunk);
            if (p == null) return;
            remaining -= chunk.length;
            yield totalBytes > 0 ? sentBytes / totalBytes : 0.0;
          }
        } finally {
          await raf.close();
        }
      }

      // 确保文件内容全部写入内核,再发完成标记(保持帧序)
      await socket.flush();
      // 发送完成标记(携带 MD5 供接收方校验)——发送期间增量累加结果
      final md5 = md5Acc.close();
      _sendJson(socket, {
        'type': 'file_done',
        'id': transferId,
        'md5': md5,
      });
      debugPrint('[ChatServer] File sent to $peerId: $fileName');
    } catch (e) {
      _sendJson(socket, {'type': 'file_error', 'id': transferId, 'error': e.toString()});
      debugPrint('[ChatServer] File send error: $e');
      // 抛给上层,让发送方消息能标记为失败
      rethrow;
    }
  }

  /// 等待对方回复 file_ready;对端不回时超时兜底继续
  /// (超时较长(30s):接收端在 .part writer 就绪后才回 file_ready,
  /// 多文件并发时准备 IO 排队,超时过短会触发"强推",反而导致接收端
  /// 等待缓冲溢出 abort。)
  /// 等待期间以 100ms 粒度轮询 [isCancelled],用户取消后立即返回,
  /// 由上层 sendChunk 的取消检查中止发送,避免"点叉号后仍重连重发"。
  Future<void> _waitForReady(String transferId,
      {bool Function()? isCancelled}) async {
    final completer = Completer<void>();
    _fileReadyCompleters[transferId] = completer;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    try {
      while (!(isCancelled?.call() ?? false)) {
        final remain = deadline.difference(DateTime.now());
        if (remain <= Duration.zero) {
          debugPrint('[ChatServer] file_ready timeout for $transferId, force push');
          return;
        }
        try {
          await completer.future.timeout(
            remain < const Duration(milliseconds: 100)
                ? remain
                : const Duration(milliseconds: 100),
          );
          return;
        } catch (_) {
          // 等待超时片段,继续轮询取消状态
        }
      }
      debugPrint('[ChatServer] file_ready cancelled for $transferId');
    } finally {
      _fileReadyCompleters.remove(transferId);
    }
  }

  /// 向已连接的 peer 发送 file_ready(接收方回复,发送方据此开始推数据)
  bool sendFileReady(String peerId, String transferId) {
    final peer = _connectedPeers[peerId];
    if (peer == null) return false;
    return _sendJson(peer.socket, {
      'type': 'file_ready',
      'id': transferId,
    });
  }

  /// 向已连接的 peer 发送 file_error(接收方校验失败时回发,发送方据此标记失败)
  bool sendFileError(String peerId, String transferId, String error) {
    final peer = _connectedPeers[peerId];
    if (peer == null) return false;
    return _sendJson(peer.socket, {
      'type': 'file_error',
      'id': transferId,
      'error': error,
    });
  }

  /// 处理客户端连接
  void _handleClient(Socket client) {
    // 禁用 Nagle 算法:避免局域网延迟 ACK 交互造成吞吐骤降
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    final remoteAddr = '${client.remoteAddress.address}:${client.remotePort}';
    final ip = client.remoteAddress.address;
    debugPrint('[ChatServer] Client connected: $remoteAddr');

    final peerInfo = _PeerInfo(socket: client, ip: ip);
    _pendingPeers.add(peerInfo);

    // 重置缓冲区,每个客户端独立。
    // E方案: 用 BytesBuilder 累积(BytesBuilder 内部按 Uint8List 块持有,
    // 不逐字节装箱),解析时 takeBytes 合并为单块 Uint8List 后零拷贝切帧。
    final buffer = BytesBuilder(copy: false);

    peerInfo.sub = client.listen(
      (data) {
        buffer.add(data);
        _processBuffer(client, buffer, remoteAddr, peerInfo);
      },
      onDone: () {
        debugPrint('[ChatServer] Client disconnected: $remoteAddr');
        _pendingPeers.remove(peerInfo);
        _removePeerIfCurrent(peerInfo);
      },
      onError: (error) {
        debugPrint('[ChatServer] Client error: $error');
        _pendingPeers.remove(peerInfo);
        _removePeerIfCurrent(peerInfo);
      },
    );
  }

  /// 暂停某 peer 的 socket 数据读取(流式背压:接收端磁盘写慢时暂停,
  /// TCP 窗口自动填满,发送方 flush 阻塞自然减速,替代 pending 堆积 abort)。
  bool pausePeerRead(String peerId) {
    final peer = _connectedPeers[peerId];
    if (peer == null || peer.sub == null) return false;
    peer.sub!.pause();
    return true;
  }

  /// 恢复某 peer 的 socket 数据读取(背压解除后继续消费)
  bool resumePeerRead(String peerId) {
    final peer = _connectedPeers[peerId];
    if (peer == null || peer.sub == null) return false;
    peer.sub!.resume();
    return true;
  }

  /// 处理缓冲区中的数据（标记 + TLV 格式，支持跨包解析）
  /// E方案: 缓冲改为 BytesBuilder,每次调用先 takeBytes 合并为单块
  /// Uint8List,帧切片用 sublistView 零拷贝视图(不再逐帧 sublist 拷贝),
  /// 未消费的剩余字节以视图形式放回 builder,供下一轮/下一包继续解析。
  void _processBuffer(Socket client, BytesBuilder buffer, String remoteAddr, _PeerInfo peerInfo) {
    final bytes = buffer.takeBytes();
    var processed = 0;
    // 已消费字节偏移:替代每帧 removeRange(0, n) 的 O(n) 移位,
    // 大文件接收时逐帧移位是主 isolate 的隐藏开销,统一在批尾处理一次
    var consumed = 0;
    while (true) {
      if (peerInfo.frameType == null) {
        if (bytes.length - consumed < 5) break; // 1 标记 + 4 长度
        peerInfo.frameType = bytes[consumed];
        peerInfo.msgLen = (bytes[consumed + 1] << 24) |
            (bytes[consumed + 2] << 16) |
            (bytes[consumed + 3] << 8) |
            bytes[consumed + 4];
        consumed += 5;
      }

      if (bytes.length - consumed < peerInfo.msgLen) break;

      final chunk = Uint8List.sublistView(bytes, consumed, consumed + peerInfo.msgLen);
      consumed += peerInfo.msgLen;
      final frameType = peerInfo.frameType!;
      peerInfo.msgLen = -1;
      peerInfo.frameType = null;

      // 每批最多同步解析 kMaxFramesPerBatch 帧:大文件接收时 socket 数据
      // 连续到达,若一次性 while 解析完缓冲里所有帧,主 isolate 会被长时间
      // 占满,接收端 UI 事件得不到执行 → 界面卡死。达到上限后让出事件循环
      // (Timer.run),剩余数据下一轮再解析,UI 得以正常刷新。
      processed++;
      if (processed >= kMaxFramesPerBatch && bytes.length - consumed >= 5) {
        // 未消费部分零拷贝放回,让出事件循环
        if (consumed < bytes.length) {
          buffer.add(Uint8List.sublistView(bytes, consumed));
        }
        Timer.run(() => _processBuffer(client, buffer, remoteAddr, peerInfo));
        return;
      }

      // 新版文件数据块('G'):自带 transferId,同连接并发多文件不串线
      if (frameType == kFileChunkV2Marker) {
        try {
          if (chunk.length < 4) continue;
          final tidLen = (chunk[0] << 24) |
              (chunk[1] << 16) |
              (chunk[2] << 8) |
              chunk[3];
          if (chunk.length < 4 + tidLen) continue;
          final tid = utf8.decode(Uint8List.sublistView(chunk, 4, 4 + tidLen));
          final data = Uint8List.sublistView(chunk, 4 + tidLen);
          onFileChunk?.call(tid, data);
        } catch (e, st) {
          // 恶意/损坏帧:记录并跳过,不能因此取消 socket 监听
          debugPrint('[ChatServer] v2 chunk parse error: $e\n$st');
        }
        continue;
      }

      try {
        final json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
        final type = json['type'] as String? ?? '';
        debugPrint(
            '[ChatServer] recv from $remoteAddr: type=$type senderId=${json['senderId']} len=${chunk.length}');

        // 识别 peer ID：从消息中提取 senderId 并注册
        if (peerInfo.peerId == null && json['senderId'] != null) {
          final senderId = json['senderId'] as String;
          peerInfo.peerId = senderId;
          peerInfo.tcpPort = json['tcpPort'] as int? ?? 0;
          _pendingPeers.remove(peerInfo);
          _connectedPeers[senderId] = peerInfo;
          debugPrint('[ChatServer] Peer identified: $senderId from $remoteAddr');
          onPeerConnected?.call(senderId, peerInfo.ip, peerInfo.tcpPort);
        }

        switch (type) {
          case 'hello':
            // 握手消息，仅用于识别 peer，不转发为聊天消息
            break;
          case 'text':
          case 'system':
            final msg = ChatMessage.fromJson(json);
            debugPrint('[ChatServer] onMessage -> peerId=${msg.senderId} content=${msg.content}');
            onMessage?.call(msg);
            break;
          case 'file_meta':
            onFileMeta?.call(
              json['id'] as String? ?? '',
              json['fileName'] as String? ?? '',
              json['fileSize'] as int? ?? 0,
              peerInfo.peerId ?? '',
            );
            break;
          case 'file_ready':
            debugPrint('[ChatServer] file_ready from $remoteAddr: ${json['id']}');
            _fileReadyCompleters.remove(json['id'] as String? ?? '')?.complete();
            break;
          case 'file_cancel':
            debugPrint('[ChatServer] file_cancel from $remoteAddr: ${json['id']}');
            onFileControl?.call(json['id'] as String? ?? '', 'file_cancel');
            break;
          case 'file_done':
            debugPrint('[ChatServer] file_done from $remoteAddr: ${json['id']}');
            onFileDone?.call(
                json['id'] as String? ?? '', json['md5'] as String? ?? '');
            break;
          case 'file_error':
            debugPrint('[ChatServer] file_error from $remoteAddr: ${json['error']}');
            onFileError?.call(
                json['id'] as String? ?? '', json['error'] as String? ?? '');
            break;
          default:
            debugPrint('[ChatServer] Unknown message type: $type');
        }
      } catch (e, st) {
        debugPrint('[ChatServer] Parse error: $e\n$st');
      }
    }
    // 循环正常退出(数据不足等下一包):未消费的剩余字节以零拷贝视图放回,
    // 保持 buffer 从下一未解析字节开始(与逐帧 removeRange 语义一致)
    if (consumed < bytes.length) {
      buffer.add(Uint8List.sublistView(bytes, consumed));
    }
  }

  void dispose() {
    stop();
  }
}