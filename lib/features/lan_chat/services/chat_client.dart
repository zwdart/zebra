import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/file_transfer_session.dart' show kSmallFileThresholdBytes;
import 'chat_server.dart';

/// TCP 客户端
/// 向其他设备发送消息和文件，同时监听对方通过同一连接发回的消息
class ChatClient {
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub; // socket 数据订阅(背压 pause/resume 用)
  bool _isConnected = false;
  final List<int> _buffer = [];
  int _msgLen = -1;
  int? _frameType; // 当前帧类型（kJsonMarker/kFileMarker）
  String? _currentTransferId; // 当前文件传输 ID（file_meta 之后有效）

  OnMessageReceived? onMessage;
  OnFileMetaReceived? onFileMeta;
  OnFileChunkReceived? onFileChunk;
  OnFileDoneReceived? onFileDone;
  OnFileErrorReceived? onFileError;
  OnFileControlReceived? onFileControl;
  OnLog? onLog;

  /// 等待对方 file_ready 的 completer(按 transferId;值表示对端是否支持 v2 帧)
  final Map<String, Completer<bool>> _fileReadyCompleters = {};

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
  /// 先发元信息，再发文件内容（'F' 标记数据块），最后发完成标记
  /// [filePath] 可为空(流式源场景);[readStream] 提供按块读取的流,
  /// 调用方需保证流已定位到 [offset](原生直读流重开时 seek/skip),
  /// 有流时直接消费流,否则从文件路径读取。
  /// [offset] 为断点续传起始字节,>0 时从该位置继续发送;
  /// [beforeChunk] 每块发送前调用(用于暂停等待),返回后继续;
  /// [isCancelled] 每块发送前检查,返回 true 时中止发送(不发完成标记)。
  /// 发送前统一等待对方 file_ready(旧版本对端不回,5s 超时兜底继续);
  /// 对方支持 v2 帧时使用自带 transferId 的 'G' 帧,否则回退旧 'F' 帧。
  /// 发送过程增量计算 MD5,随 file_done 一并发出,供接收方校验。
  Stream<double> sendFile({
    required String transferId,
    String? filePath,
    required String fileName,
    required int fileSize,
    int offset = 0,
    Stream<List<int>>? readStream,
    Future<void> Function()? beforeChunk,
    bool Function()? isCancelled,
    void Function(String)? onLog,
  }) async* {
    if (_socket == null) return;

    // 用户可能在重连/等待期间点了取消:取消后不再发 meta、不再推数据
    if (isCancelled?.call() ?? false) {
      debugPrint('[ChatClient] File send cancelled before meta: $fileName');
      return;
    }

    // 发送文件元信息
    // S4: 压缩传输条件——仅大文件(filePath 源)且从头发送(offset==0),
    // 压缩流不支持按字节断点续传,故续传场景禁用压缩;
    // fileSize 仍为原始大小(接收端进度/校验按原始字节),压缩与否由该标志告知
    final compressed = offset == 0 &&
        readStream == null &&
        filePath != null &&
        fileSize > kSmallFileThresholdBytes;
    final meta = {
      'type': 'file_meta',
      'id': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
      'offset': offset,
      'compressed': compressed,
    };
    _sendJson(meta);

    // 等待对方接收就绪;旧版本对端不会回复,超时兜底后继续(并回退旧帧)
    final supportsV2 = await _waitForReady(transferId, isCancelled: isCancelled);

    // 发送文件内容
    try {
      final totalBytes =
          readStream != null ? fileSize : await File(filePath ?? '').length();
      var sentBytes = offset;
      // S3: filePath 源发送完成后在后台 isolate 一次性计算 MD5(不占主 isolate);
      // readStream 源(无法重读文件)保留逐块增量累加
      final md5Acc = readStream != null ? Md5Accumulator() : null;

      // 发送一块数据:帧封装 + MD5 + 进度;返回 null 表示已取消
      // S2: 每 kChunksPerFlush 块 flush 一次(替代逐块 flush),减少系统调用;
      // 接收端已有 pause/resume 背压与 TCP 窗口节流,无需逐块 flush 施加背压
      // [progressBytes] 压缩传输时传入"原始字节数"作为进度口径
      // (发送的是压缩字节,但进度/剩余时间应按原始文件计算)
      var chunksSinceFlush = 0;
      Future<double?> sendChunk(List<int> chunk, {int? progressBytes}) async {
        // 暂停等待(恢复后继续;取消会唤醒等待)
        await beforeChunk?.call();
        // 取消检查:中止且不发完成标记(放在暂停之后,避免暂停期间取消多发一块)
        if (isCancelled?.call() ?? false) {
          debugPrint('[ChatClient] File send cancelled: $fileName');
          return null;
        }
        if (chunk.isEmpty) {
          return totalBytes > 0 ? sentBytes / totalBytes : 0.0;
        }

        if (supportsV2) {
          // 新版帧:'G' + 4字节内容长度 + [tidLen(4) + transferId + 数据]
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
        } else {
          // 旧版帧:'F' + 4字节数据长度 + 数据
          final size = chunk.length;
          _socket!.add(<int>[
            kFileMarker,
            (size >> 24) & 0xFF,
            (size >> 16) & 0xFF,
            (size >> 8) & 0xFF,
            size & 0xFF,
          ]);
        }
        _socket!.add(chunk);
        md5Acc?.add(chunk);
        chunksSinceFlush++;
        if (chunksSinceFlush >= kChunksPerFlush) {
          await _socket!.flush();
          chunksSinceFlush = 0;
        }

        sentBytes += progressBytes ?? chunk.length;
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
          // S1: 1MB 大块减少系统调用与帧头开销;接收端已有 pause/resume
          // 背压保护,不再需要 256KB 细粒度块来避免缓冲溢出
          const chunkSize = 1024 * 1024;
          // S4: 压缩传输——原始块经流式 zlib 压缩后发送;
          // 压缩器内部可能缓冲,add 可能返回空,进度按原始字节计
          final compressor = compressed ? StreamCompressor() : null;
          while (remaining > 0) {
            final readLen = remaining < chunkSize ? remaining : chunkSize;
            final chunk = await raf.read(readLen);
            if (chunk.isEmpty) break;
            if (compressor != null) {
              final wire = compressor.add(chunk);
              if (wire.isNotEmpty) {
                final p = await sendChunk(wire, progressBytes: chunk.length);
                if (p == null) return;
              } else {
                // 压缩器内部缓冲,无输出:进度仍需推进(按原始字节)
                sentBytes += chunk.length;
                yield totalBytes > 0 ? sentBytes / totalBytes : 0.0;
              }
            } else {
              final p = await sendChunk(chunk);
              if (p == null) return;
            }
            remaining -= chunk.length;
            yield totalBytes > 0 ? sentBytes / totalBytes : 0.0;
          }
          // S4: 压缩收尾块(含 checksum)
          if (compressor != null) {
            final tail = compressor.close();
            if (tail.isNotEmpty) {
              final p = await sendChunk(tail);
              if (p == null) return;
            }
          }
        } finally {
          await raf.close();
        }
      }

      // 确保文件内容全部写入内核,再发完成标记(保持帧序)
      await _socket!.flush();
      // S3: 发送完成标记(携带 MD5 供接收方校验)。
      // filePath 源在后台 isolate 重读文件计算(与接收端语义对称,从 offset 起算);
      // readStream 源用逐块增量累加结果。
      String md5;
      if (md5Acc != null) {
        md5 = md5Acc.close();
      } else if (filePath != null && filePath.isNotEmpty) {
        md5 = await computeFileMd5Segment(filePath, offset);
      } else {
        md5 = ''; // 兜底:无路径可重读,发空校验值(接收端跳过校验)
      }
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
          debugPrint('[ChatClient] file_ready timeout for $transferId, use v2 frames');
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
      debugPrint('[ChatClient] file_ready cancelled for $transferId');
      return true;
    } finally {
      _fileReadyCompleters.remove(transferId);
    }
  }

  /// 发送 file_ready(接收方回复,发送方据此开始推数据)
  /// 携带 chunkV2 标记,表明本端支持自带 transferId 的新版数据帧
  bool sendFileReady(String transferId) {
    if (_socket == null) return false;
    _sendJson({'type': 'file_ready', 'id': transferId, 'chunkV2': true});
    return true;
  }

  /// 发送 file_error(接收方校验失败时回发,发送方据此标记失败)
  void sendFileError(String transferId, String error) {
    _sendJson({'type': 'file_error', 'id': transferId, 'error': error});
  }

  /// 发送文件控制消息(pause/resume/cancel)
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
  void _handleData(List<int> data) {
    _buffer.addAll(data);

    var processed = 0;
    // 已消费字节偏移:替代每帧 removeRange(0, n) 的 O(n) 移位,
    // 大文件接收时逐帧移位是主 isolate 的隐藏开销,统一在批尾压缩一次
    var consumed = 0;
    while (true) {
      if (_frameType == null) {
        if (_buffer.length - consumed < 5) break; // 1 标记 + 4 长度
        _frameType = _buffer[consumed];
        _msgLen = (_buffer[consumed + 1] << 24) |
            (_buffer[consumed + 2] << 16) |
            (_buffer[consumed + 3] << 8) |
            _buffer[consumed + 4];
        consumed += 5;
      }

      if (_buffer.length - consumed < _msgLen) break;

      final chunk = _buffer.sublist(consumed, consumed + _msgLen);
      consumed += _msgLen;
      final frameType = _frameType!;
      _msgLen = -1;
      _frameType = null;

      // 每批最多同步解析 kMaxFramesPerBatch 帧(原因同 ChatServer._processBuffer):
      // 大文件接收时数据连续到达,若一次性解析完会长时间占用主 isolate,
      // 接收端 UI 事件得不到执行 → 界面卡死;达到上限后让出事件循环分批继续。
      processed++;
      if (processed >= kMaxFramesPerBatch && _buffer.length - consumed >= 5) {
        _buffer.removeRange(0, consumed);
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
          final tid = utf8.decode(chunk.sublist(4, 4 + tidLen));
          final data = chunk.sublist(4 + tidLen);
          onFileChunk?.call(tid, data);
        } catch (e, st) {
          // 恶意/损坏帧:记录并跳过,不能因此取消 socket 监听
          debugPrint('[ChatClient] v2 chunk parse error: $e\n$st');
        }
        continue;
      }

      // 旧版文件数据块：不解析 JSON，直接回调(无 transferId,依赖 currentTransferId)
      if (frameType == kFileMarker) {
        final tid = _currentTransferId;
        if (tid != null) {
          onFileChunk?.call(tid, chunk);
        } else {
          debugPrint('[ChatClient] file chunk dropped: no active transfer');
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
            _currentTransferId = json['id'] as String? ?? '';
            onFileMeta?.call(
              json['id'] as String? ?? '',
              json['fileName'] as String? ?? '',
              json['fileSize'] as int? ?? 0,
              '',
              json['offset'] as int? ?? 0,
              json['compressed'] == true,
            );
            break;
          case 'file_ready':
            debugPrint('[ChatClient] file_ready: transfer=${json['id']}');
            _fileReadyCompleters.remove(json['id'] as String? ?? '')
                ?.complete(json['chunkV2'] == true);
            break;
          case 'file_pause':
          case 'file_resume':
          case 'file_cancel':
            debugPrint('[ChatClient] file control: ${json['type']} ${json['id']}');
            onFileControl?.call(json['id'] as String? ?? '', json['type'] as String? ?? '');
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
    // 循环正常退出(数据不足等下一包):一次性移除已消费字节,
    // 保持 _buffer 从下一未解析字节开始(与逐帧 removeRange 语义一致)
    if (consumed > 0) {
      _buffer.removeRange(0, consumed);
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
    _currentTransferId = null;
    _socket?.destroy();
    _socket = null;
  }

  void dispose() {
    disconnect();
  }
}