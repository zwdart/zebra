import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';

/// 帧类型标记
const int kJsonMarker = 0x4A; // 'J'
const int kFileMarker = 0x46; // 'F' 旧版文件数据块(无 transferId,依赖 currentTransferId)
const int kFileChunkV2Marker = 0x47; // 'G' 新版文件数据块(自带 transferId,支持同连接并发多文件)

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
/// TCP 文件元信息接收回调（peerId 为对方的设备 ID;offset 为断点续传起始字节）
typedef OnFileMetaReceived = void Function(
    String transferId, String fileName, int fileSize, String peerId, int offset);
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
  String? peerId;
  int tcpPort = 0;
  int msgLen = -1; // 当前帧数据长度，跨 TCP 包保持
  int? frameType; // 当前帧类型（kJsonMarker/kFileMarker）
  String? currentTransferId; // 当前文件传输 ID（file_meta 之后有效）

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

  /// 等待对方 file_ready 的 completer(按 transferId;值表示对端是否支持 v2 帧)
  final Map<String, Completer<bool>> _fileReadyCompleters = {};

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
  Future<int> start({int port = 19423}) async {
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
  /// 先发元信息，再发文件内容，格式与 ChatClient.sendFile 一致
  /// [offset] 为断点续传起始字节,>0 时从该位置继续发送;
  /// [beforeChunk] 每块发送前调用(用于暂停等待);
  /// [isCancelled] 每块发送前检查,返回 true 时中止发送。
  /// 发送前统一等待对方 file_ready(旧版本对端不回,5s 超时兜底继续);
  /// 对方支持 v2 帧时使用自带 transferId 的 'G' 帧(同连接并发多文件不串线),
  /// 否则回退旧 'F' 帧。发送过程增量计算 MD5,随 file_done 一并发出。
  /// [filePath] 可为空(流式源场景);[readStream] 提供按块读取的流,
  /// 调用方需保证流已定位到 [offset](原生直读流重开时 seek/skip),
  /// 有流时直接消费流,否则从文件路径读取。
  Stream<double> sendFile({
    required String peerId,
    required String transferId,
    String? filePath,
    required String fileName,
    required int fileSize,
    int offset = 0,
    Stream<List<int>>? readStream,
    Future<void> Function()? beforeChunk,
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

    // 发送文件元信息
    _sendJson(socket, {
      'type': 'file_meta',
      'id': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
      'offset': offset,
    });

    // 等待对方接收就绪;旧版本对端不会回复,超时兜底后继续(并回退旧帧)
    final supportsV2 = await _waitForReady(transferId, isCancelled: isCancelled);

    // 发送文件内容
    try {
      final totalBytes =
          readStream != null ? fileSize : await File(filePath ?? '').length();
      var sentBytes = offset;
      final md5Acc = Md5Accumulator(); // 增量计算文件 MD5

      // 发送一块数据:帧封装 + MD5 + 进度;返回 null 表示已取消
      Future<double?> sendChunk(List<int> chunk) async {
        // 暂停等待(恢复后继续;取消会唤醒等待)
        await beforeChunk?.call();
        // 取消检查:中止且不发完成标记(放在暂停之后,避免暂停期间取消多发一块)
        if (isCancelled?.call() ?? false) {
          debugPrint('[ChatServer] File send cancelled: $fileName');
          return null;
        }
        if (chunk.isEmpty) {
          return totalBytes > 0 ? sentBytes / totalBytes : 0.0;
        }

        if (supportsV2) {
          // 新版帧:'G' + 4字节内容长度 + [tidLen(4) + transferId + 数据]
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
        } else {
          // 旧版帧:'F' + 4字节数据长度 + 数据
          final size = chunk.length;
          socket.add(<int>[
            kFileMarker,
            (size >> 24) & 0xFF,
            (size >> 16) & 0xFF,
            (size >> 8) & 0xFF,
            size & 0xFF,
          ]);
        }
        socket.add(chunk);
        md5Acc.add(chunk);
        // 逐块 flush 施加 TCP 背压:让发送速率跟随接收端消费速率,
        // 进度=真实已写出字节,避免发送端进度虚高而接收端滞后
        await socket.flush();

        sentBytes += chunk.length;
        return totalBytes > 0 ? sentBytes / totalBytes : 0.0;
      }

      if (readStream != null) {
        // 流式源:调用方保证流已定位到 offset(原生直读流重开时 seek/skip),
        // 直接逐块消费,不再在此处跳过字节
        await for (final chunk in readStream) {
          final p = await sendChunk(chunk);
          if (p == null) return;
          yield p;
        }
      } else {
        // 文件路径:RandomAccessFile 按 1MB 大块读取
        final raf = await File(filePath ?? '').open();
        try {
          await raf.setPosition(offset);
          var remaining = totalBytes - offset;
          // 256KB 块:更细粒度的 TCP 背压与接收端事件循环交错,
          // 避免接收端单次数据事件突发堆积 pending 导致缓冲溢出(1MB 块曾触发)
          const chunkSize = 256 * 1024;
          while (remaining > 0) {
            final readLen = remaining < chunkSize ? remaining : chunkSize;
            final chunk = await raf.read(readLen);
            if (chunk.isEmpty) break;
            final p = await sendChunk(chunk);
            if (p == null) return;
            remaining -= chunk.length;
            yield p;
          }
        } finally {
          await raf.close();
        }
      }

      // 确保文件内容全部写入内核,再发完成标记(保持帧序)
      await socket.flush();
      // 发送完成标记(携带 MD5 供接收方校验)
      _sendJson(socket, {
        'type': 'file_done',
        'id': transferId,
        'md5': md5Acc.close(),
      });
      debugPrint('[ChatServer] File sent to $peerId: $fileName');
    } catch (e) {
      _sendJson(socket, {'type': 'file_error', 'id': transferId, 'error': e.toString()});
      debugPrint('[ChatServer] File send error: $e');
      // 抛给上层,让发送方消息能标记为失败
      rethrow;
    }
  }

  /// 等待对方回复 file_ready;返回对端是否支持 v2 帧
  /// (旧版本对端不回,超时兜底仍按 v2 帧发送——本端两端同版本,
  /// v2 'G' 帧自带 transferId,多文件并发不会串线/丢帧;
  /// 回退无 transferId 的旧 'F' 帧在并发下依赖单一 currentTransferId,
  /// 会被其他文件的 file_meta 覆盖导致 chunk 被丢弃)
  /// 等待期间以 100ms 粒度轮询 [isCancelled],用户取消后立即返回,
  /// 由上层 sendChunk 的取消检查中止发送,避免"点叉号后仍重连重发"。
  /// 超时较长(30s):接收端在 .part writer 就绪后才回 file_ready,
  /// 多文件并发时准备 IO 排队,超时过短会触发"强推",反而导致接收端
  /// 等待缓冲溢出 abort。
  Future<bool> _waitForReady(String transferId,
      {bool Function()? isCancelled}) async {
    final completer = Completer<bool>();
    _fileReadyCompleters[transferId] = completer;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    try {
      while (!(isCancelled?.call() ?? false)) {
        final remain = deadline.difference(DateTime.now());
        if (remain <= Duration.zero) {
          debugPrint('[ChatServer] file_ready timeout for $transferId, use v2 frames');
          return true;
        }
        try {
          return await completer.future.timeout(
            remain < const Duration(milliseconds: 100)
                ? remain
                : const Duration(milliseconds: 100),
          );
        } catch (_) {
          // 等待超时片段,继续轮询取消状态
        }
      }
      debugPrint('[ChatServer] file_ready cancelled for $transferId');
      return true;
    } finally {
      _fileReadyCompleters.remove(transferId);
    }
  }

  /// 向已连接的 peer 发送 file_ready(接收方回复,发送方据此开始推数据)
  /// 携带 chunkV2 标记,表明本端支持自带 transferId 的新版数据帧
  bool sendFileReady(String peerId, String transferId) {
    final peer = _connectedPeers[peerId];
    if (peer == null) return false;
    return _sendJson(peer.socket, {
      'type': 'file_ready',
      'id': transferId,
      'chunkV2': true,
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

    // 重置缓冲区，每个客户端独立
    final buffer = <int>[];

    client.listen(
      (data) {
        buffer.addAll(data);
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

  /// 处理缓冲区中的数据（标记 + TLV 格式，支持跨包解析）
  void _processBuffer(Socket client, List<int> buffer, String remoteAddr, _PeerInfo peerInfo) {
    while (true) {
      if (peerInfo.frameType == null) {
        if (buffer.length < 5) break; // 1 标记 + 4 长度
        peerInfo.frameType = buffer[0];
        peerInfo.msgLen = (buffer[1] << 24) |
            (buffer[2] << 16) |
            (buffer[3] << 8) |
            buffer[4];
        buffer.removeRange(0, 5);
      }

      if (buffer.length < peerInfo.msgLen) break;

      final chunk = buffer.sublist(0, peerInfo.msgLen);
      buffer.removeRange(0, peerInfo.msgLen);
      final frameType = peerInfo.frameType!;
      peerInfo.msgLen = -1;
      peerInfo.frameType = null;

      // 新版文件数据块('G'):自带 transferId,同连接并发多文件不串线
      if (frameType == kFileChunkV2Marker) {
        try {
          if (chunk.length < 4) continue;
          final tidLen = (chunk[0] << 24) |
              (chunk[1] << 16) |
              (chunk[2] << 8) |
              chunk[3];
          if (chunk.length < 4 + tidLen) continue;
          final tid = utf8.decode(chunk.sublist(4, 4 + tidLen));
          final data = chunk.sublist(4 + tidLen);
          onFileChunk?.call(tid, data);
        } catch (e, st) {
          // 恶意/损坏帧:记录并跳过,不能因此取消 socket 监听
          debugPrint('[ChatServer] v2 chunk parse error: $e\n$st');
        }
        continue;
      }

      // 旧版文件数据块：不解析 JSON，直接回调(无 transferId,依赖 currentTransferId)
      if (frameType == kFileMarker) {
        final tid = peerInfo.currentTransferId;
        if (tid != null) {
          debugPrint('[ChatServer] file chunk from $remoteAddr: transfer=$tid ${chunk.length}B');
          onFileChunk?.call(tid, chunk);
        } else {
          debugPrint('[ChatServer] file chunk dropped: no active transfer');
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
            peerInfo.currentTransferId = json['id'] as String? ?? '';
            onFileMeta?.call(
              json['id'] as String? ?? '',
              json['fileName'] as String? ?? '',
              json['fileSize'] as int? ?? 0,
              peerInfo.peerId ?? '',
              json['offset'] as int? ?? 0,
            );
            break;
          case 'file_ready':
            debugPrint('[ChatServer] file_ready from $remoteAddr: ${json['id']}');
            _fileReadyCompleters.remove(json['id'] as String? ?? '')
                ?.complete(json['chunkV2'] == true);
            break;
          case 'file_pause':
          case 'file_resume':
          case 'file_cancel':
            debugPrint('[ChatServer] file control from $remoteAddr: ${json['type']} ${json['id']}');
            onFileControl?.call(json['id'] as String? ?? '', json['type'] as String? ?? '');
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
  }

  void dispose() {
    stop();
  }
}