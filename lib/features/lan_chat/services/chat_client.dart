import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import 'chat_server.dart';

/// TCP 客户端
/// 向其他设备发送消息和文件，同时监听对方通过同一连接发回的消息
class ChatClient {
  Socket? _socket;
  bool _isConnected = false;
  final List<int> _buffer = [];
  int _msgLen = -1;
  int? _frameType; // 当前帧类型（kJsonMarker/kFileMarker）
  String? _currentTransferId; // 当前文件传输 ID（file_meta 之后有效）

  OnMessageReceived? onMessage;
  OnFileMetaReceived? onFileMeta;
  OnFileChunkReceived? onFileChunk;
  OnFileDoneReceived? onFileDone;
  OnLog? onLog;

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
      _isConnected = true;

      _socket!.listen(
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
  Stream<double> sendFile({
    required String transferId,
    required String filePath,
    required String fileName,
    required int fileSize,
    void Function(String)? onLog,
  }) async* {
    if (_socket == null) return;

    // 发送文件元信息
    final meta = {
      'type': 'file_meta',
      'id': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
    };
    _sendJson(meta);
    await Future.delayed(const Duration(milliseconds: 100));

    // 发送文件内容
    try {
      final file = File(filePath);
      final totalBytes = await file.length();
      var sentBytes = 0;

      final stream = file.openRead();
      await for (final chunk in stream) {
        // 文件数据块：'F' 标记 + 4字节长度 + 原始数据
        final size = chunk.length;
        final header = <int>[
          kFileMarker,
          (size >> 24) & 0xFF,
          (size >> 16) & 0xFF,
          (size >> 8) & 0xFF,
          size & 0xFF,
        ];

        _socket!.add(header);
        _socket!.add(chunk);
        await _socket!.flush();

        sentBytes += chunk.length;
        yield totalBytes > 0 ? sentBytes / totalBytes : 0.0;
      }

      // 发送完成标记
      _sendJson({'type': 'file_done', 'id': transferId});
      debugPrint('[ChatClient] File sent: $fileName');
    } catch (e) {
      _sendJson({'type': 'file_error', 'id': transferId, 'error': e.toString()});
      debugPrint('[ChatClient] File send error: $e');
      // 抛给上层,让发送方消息能标记为失败
      rethrow;
    }
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
    debugPrint('[ChatClient] recv ${data.length} bytes');
    _buffer.addAll(data);

    while (true) {
      if (_frameType == null) {
        if (_buffer.length < 5) break; // 1 标记 + 4 长度
        _frameType = _buffer[0];
        _msgLen = (_buffer[1] << 24) |
            (_buffer[2] << 16) |
            (_buffer[3] << 8) |
            _buffer[4];
        _buffer.removeRange(0, 5);
      }

      if (_buffer.length < _msgLen) break;

      final chunk = _buffer.sublist(0, _msgLen);
      _buffer.removeRange(0, _msgLen);
      final frameType = _frameType!;
      _msgLen = -1;
      _frameType = null;

      // 文件数据块：不解析 JSON，直接回调
      if (frameType == kFileMarker) {
        final tid = _currentTransferId;
        if (tid != null) {
          debugPrint('[ChatClient] file chunk: transfer=$tid ${chunk.length}B');
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
            );
            break;
          case 'file_done':
            debugPrint('[ChatClient] file_done: transfer=${json['id']}');
            onFileDone?.call(json['id'] as String? ?? '');
            break;
          case 'file_error':
            debugPrint('[ChatClient] file_error: ${json['error']}');
            onFileDone?.call(json['id'] as String? ?? '');
            break;
          default:
            debugPrint('[ChatClient] unknown frame type: $type');
        }
      } catch (e, st) {
        debugPrint('[ChatClient] frame parse error: $e\n$st');
      }
    }
  }

  /// 断开连接
  void disconnect() {
    _isConnected = false;
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