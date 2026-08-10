import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import 'chat_server.dart';

/// TCP 客户端
/// 向其他设备发送消息和文件，同时监听对方通过同一连接发回的消息
class ChatClient {
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub; // socket 数据订阅(背压 pause/resume 用)
  bool _isConnected = false;
  // E方案: 接收缓冲改用 BytesBuilder 累积(BytesBuilder 内部按 Uint8List
  // 块持有,不逐字节装箱),解析时 takeBytes 合并后零拷贝切帧
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _msgLen = -1;
  int? _frameType; // 当前帧类型(kJsonMarker/kFileChunkV2Marker)

  OnMessageReceived? onMessage;
  OnFileMetaReceived? onFileMeta;
  OnFileChunkReceived? onFileChunk;
  OnFileDoneReceived? onFileDone;
  OnFileErrorReceived? onFileError;
  OnFileControlReceived? onFileControl;
  OnLog? onLog;

  /// 等待对方 file_ready 的 completer(按 transferId)
  final Map<String, Completer<void>> _fileReadyCompleters = {};

  bool get isConnected => _isConnected;

  /// 连接到远程设备
  Future<bool> connect(String ip, int port) async {
    try {
      debugPrint('[ChatClient] Connecting to $ip:$port ...');
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      // 禁用 Nagle 算法:避免局域网延迟 ACK 交互造成吞吐骤降
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _isConnected = true;

      _sub = _socket!.listen(
        (data) {
          _handleData(data);
        },
        onDone: () {
          _isConnected = false;
          debugPrint('[ChatClient] Disconnected from $ip:$port');
        },
        onError: (error) {
          _isConnected = false;
          debugPrint('[ChatClient] Error: $error');
        },
      );

      debugPrint('[ChatClient] Connected to $ip:$port');
      return true;
    } catch (e, st) {
      _isConnected = false;
      debugPrint('[ChatClient] Connection FAILED to $ip:$port: $e\n$st');
      return false;
    }
  }

  /// 暂停 socket 数据读取(流式背压:接收端磁盘写慢时暂停,
  /// TCP 窗口自动填满,发送方 flush 阻塞自然减速,替代 pending 堆积 abort)
  bool pauseRead() {
    if (_sub == null) return false;
    _sub!.pause();
    return true;
  }

  /// 恢复 socket 数据读取(背压解除后继续消费)
  bool resumeRead() {
    if (_sub == null) return false;
    _sub!.resume();
    return true;
  }

  /// 发送握手消息，让对方服务器立即识别我们（用于双向通信）
  void sendHello(String deviceId, String deviceName, int tcpPort) {
    debugPrint('[ChatClient] sendHello: deviceId=$deviceId tcpPort=$tcpPort');
    _sendJson({
      'type': 'hello',
      'senderId': deviceId,
      'senderName': deviceName,
      'tcpPort': tcpPort,
    });
  }

  /// 发送文本消息
  void sendMessage(ChatMessage msg) {
    debugPrint(
        '[ChatClient] sendMessage: type=${msg.type.name} id=${msg.id} content=${msg.content}');
    _sendJson(msg.toJson());
  }

  /// 发送文件
  /// 先发元信息，再发文件内容，最后发完成标记。
  /// 统一使用自带 transferId 的 'G' 帧(同连接并发多文件不串线),
  /// 原始字节直传(无压缩、无断点续传);发送过程增量计算 MD5,随 file_done 一并发出。
  /// [filePath] 可为空(流式源场景);[readStream] 提供按块读取的流,
  /// 有流时直接消费流,否则从文件路径读取。
  /// [isCancelled] 每块发送前检查,返回 true 时中止发送(不发完成标记)。
  Stream<double> sendFile({
    required String transferId,
    String? filePath,
    required String fileName,
    required int fileSize,
    Stream<List<int>>? readStream,
    bool Function()? isCancelled,
  }) async* {
    if (_socket == null) return;

    // 用户可能在重连/等待期间点了取消:取消后不再发 meta、不再推数据
    if (isCancelled?.call() ?? false) {
      debugPrint('[ChatClient] File send cancelled before meta: $fileName');
      return;
    }

    // 发送文件元信息(原始字节直传,无压缩、无断点续传)
    _sendJson({
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
      // 每 kChunksPerFlush 块 flush 一次,减少系统调用;
      // 接收端已有 pause/resume 背压与 TCP 窗口节流,无需逐块 flush 施加背压
      var chunksSinceFlush = 0;
      Future<double?> sendChunk(List<int> chunk) async {
        // 取消检查:中止且不发完成标记
        if (isCancelled?.call() ?? false) {
          debugPrint('[ChatClient] File send cancelled: $fileName');
          return null;
        }
        if (chunk.isEmpty) {
          return totalBytes > 0 ? sentBytes / totalBytes : 0.0;
        }

        // 'G' 帧:4字节内容长度 + [tidLen(4) + transferId + 数据]
        final tidBytes = utf8.encode(transferId);
        final contentLen = 4 + tidBytes.length + chunk.length;
        _socket!.add(<int>[
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
        _socket!.add(tidBytes);
        _socket!.add(chunk);
        chunksSinceFlush++;
        if (chunksSinceFlush >= kChunksPerFlush) {
          await _socket!.flush();
          chunksSinceFlush = 0;
        }

        sentBytes += chunk.length;
        return totalBytes > 0 ? sentBytes / totalBytes : 0.0;
      }

      if (readStream != null) {
        // 流式源:双缓冲流水线——预取下一块的同时发送当前块,
        // 掩盖 MethodChannel IPC 往返延迟(串行模式每块都要等 IPC 返回)
        final it = StreamIterator<List<int>>(readStream);
        var pending = it.moveNext(); // 预取第一块
        while (await pending) {
          final chunk = it.current;
          pending = it.moveNext(); // 立即发起下一块预取(与当前块发送并行)
          md5Acc.add(chunk);
          final p = await sendChunk(chunk);
          if (p == null) return;
          yield p;
        }
      } else {
        // 文件路径:RandomAccessFile 按 1MB 大块读取
        final raf = await File(filePath ?? '').open();
        try {
          var remaining = totalBytes;
          // 1MB 单帧 + kMaxFramesPerBatch=8 每批约 8MB,
          // 接收端主 isolate 单次占用更短,UI 更流畅
          const chunkSize = 1024 * 1024;
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
      await _socket!.flush();
      // 发送完成标记(携带 MD5 供接收方校验)——发送期间增量累加结果
      final md5 = md5Acc.close();
      _sendJson({
        'type': 'file_done',
        'id': transferId,
        'md5': md5,
      });
      debugPrint('[ChatClient] File sent: $fileName');
    } catch (e) {
      _sendJson({'type': 'file_error', 'id': transferId, 'error': e.toString()});
      debugPrint('[ChatClient] File send error: $e');
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
          debugPrint('[ChatClient] file_ready timeout for $transferId, force push');
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
      debugPrint('[ChatClient] file_ready cancelled for $transferId');
    } finally {
      _fileReadyCompleters.remove(transferId);
    }
  }

  /// 发送 file_ready(接收方回复,发送方据此开始推数据)
  bool sendFileReady(String transferId) {
    if (_socket == null) return false;
    _sendJson({'type': 'file_ready', 'id': transferId});
    return true;
  }

  /// 发送 file_error(接收方校验失败时回发,发送方据此标记失败)
  void sendFileError(String transferId, String error) {
    _sendJson({'type': 'file_error', 'id': transferId, 'error': error});
  }

  /// 发送文件取消控制消息
  void sendFileControl(String transferId, String action) {
    _sendJson({'type': 'file_$action', 'id': transferId});
  }

  /// 发送 JSON 数据（'J' 标记 + TLV 格式）
  void _sendJson(Map<String, dynamic> json) {
    if (_socket == null) return;
    try {
      final data = utf8.encode(jsonEncode(json));
      final header = <int>[
        kJsonMarker,
        (data.length >> 24) & 0xFF,
        (data.length >> 16) & 0xFF,
        (data.length >> 8) & 0xFF,
        data.length & 0xFF,
      ];
      _socket!.add(header);
      _socket!.add(data);
      _socket!.flush();
    } catch (e, st) {
      debugPrint('[ChatClient] Send error: $e\n$st');
    }
  }

  /// 处理接收的数据（标记 + TLV 格式，支持跨包拼接）
  /// E方案: 缓冲为 BytesBuilder,每次调用先 takeBytes 合并为单块
  /// Uint8List,帧切片用 sublistView 零拷贝视图,未消费剩余字节以视图放回。
  void _handleData(List<int> data) {
    _buffer.add(data);
    final bytes = _buffer.takeBytes();

    var processed = 0;
    // 已消费字节偏移:替代每帧 removeRange(0, n) 的 O(n) 移位,
    // 大文件接收时逐帧移位是主 isolate 的隐藏开销,统一在批尾处理一次
    var consumed = 0;
    while (true) {
      if (_frameType == null) {
        if (bytes.length - consumed < 5) break; // 1 标记 + 4 长度
        _frameType = bytes[consumed];
        _msgLen = (bytes[consumed + 1] << 24) |
            (bytes[consumed + 2] << 16) |
            (bytes[consumed + 3] << 8) |
            bytes[consumed + 4];
        consumed += 5;
      }

      if (bytes.length - consumed < _msgLen) break;

      final chunk = Uint8List.sublistView(bytes, consumed, consumed + _msgLen);
      consumed += _msgLen;
      final frameType = _frameType!;
      _msgLen = -1;
      _frameType = null;

      // 每批最多同步解析 kMaxFramesPerBatch 帧(原因同 ChatServer._processBuffer):
      // 大文件接收时数据连续到达,若一次性解析完会长时间占用主 isolate,
      // 接收端 UI 事件得不到执行 → 界面卡死;达到上限后让出事件循环分批继续。
      processed++;
      if (processed >= kMaxFramesPerBatch && bytes.length - consumed >= 5) {
        // 未消费部分零拷贝放回,让出事件循环
        if (consumed < bytes.length) {
          _buffer.add(Uint8List.sublistView(bytes, consumed));
        }
        Timer.run(() => _handleData(const []));
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
          debugPrint('[ChatClient] v2 chunk parse error: $e\n$st');
        }
        continue;
      }

      try {
        final json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
        final type = json['type'] as String? ?? '';
        debugPrint(
            '[ChatClient] frame: type=$type senderId=${json['senderId']} len=${chunk.length}');

        switch (type) {
          case 'hello':
            // 握手消息，仅用于识别，不显示
            break;
          case 'text':
          case 'system':
            onMessage?.call(ChatMessage.fromJson(json));
            break;
          case 'file_meta':
            onFileMeta?.call(
              json['id'] as String? ?? '',
              json['fileName'] as String? ?? '',
              json['fileSize'] as int? ?? 0,
              '',
            );
            break;
          case 'file_ready':
            debugPrint('[ChatClient] file_ready: transfer=${json['id']}');
            _fileReadyCompleters.remove(json['id'] as String? ?? '')?.complete();
            break;
          case 'file_cancel':
            debugPrint('[ChatClient] file_cancel: ${json['id']}');
            onFileControl?.call(json['id'] as String? ?? '', 'file_cancel');
            break;
          case 'file_done':
            debugPrint('[ChatClient] file_done: transfer=${json['id']}');
            onFileDone?.call(
                json['id'] as String? ?? '', json['md5'] as String? ?? '');
            break;
          case 'file_error':
            debugPrint('[ChatClient] file_error: ${json['error']}');
            onFileError?.call(
                json['id'] as String? ?? '', json['error'] as String? ?? '');
            break;
          default:
            debugPrint('[ChatClient] unknown frame type: $type');
        }
      } catch (e, st) {
        debugPrint('[ChatClient] frame parse error: $e\n$st');
      }
    }
    // 循环正常退出(数据不足等下一包):未消费的剩余字节以零拷贝视图放回,
    // 保持 _buffer 从下一未解析字节开始(与逐帧 removeRange 语义一致)
    if (consumed < bytes.length) {
      _buffer.add(Uint8List.sublistView(bytes, consumed));
    }
  }

  /// 断开连接
  void disconnect() {
    _isConnected = false;
    _sub?.cancel();
    _sub = null;
    _buffer.clear();
    _msgLen = -1;
    _frameType = null;
    _socket?.destroy();
    _socket = null;
  }

  void dispose() {
    disconnect();
  }
}