import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/room.dart';
import '../models/room_chat_message.dart';
import 'room_host.dart' show kJsonMarker, kMaxFramesPerBatch;

/// 加入成功回调(含房间信息与全量成员列表)
typedef OnRoomJoinAck = void Function(
    String roomId, String roomName, String hostId, String hostName,
    List<RoomMember> members);

/// 加入被拒回调(reason: full/not_found)
typedef OnRoomJoinReject = void Function(String reason);

/// 成员变化回调(action: joined/left;member 为变化成员;members 为全量列表)
typedef OnRoomMembers = void Function(
    String action, RoomMember member, List<RoomMember> members);

/// 房间消息回调
typedef OnRoomMessage = void Function(RoomChatMessage message);

/// 房间被房主解散回调
typedef OnRoomClose = void Function();

/// 与房主连接断开回调
typedef OnRoomDisconnected = void Function();

/// 日志回调
typedef OnLog = void Function(String log);

/// 房间客户端(成员侧)
/// 连接房主 RoomHost,收发房间消息;与单聊 ChatClient 完全独立。
class RoomClient {
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  bool _isConnected = false;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _msgLen = -1;
  int? _frameType;

  OnRoomJoinAck? onJoinAck;
  OnRoomJoinReject? onJoinReject;
  OnRoomMembers? onMembers;
  OnRoomMessage? onMessage;
  OnRoomClose? onRoomClose;
  OnRoomDisconnected? onDisconnected;
  OnLog? onLog;

  bool get isConnected => _isConnected;

  /// 连接到房主
  Future<bool> connect(String ip, int port) async {
    try {
      debugPrint('[RoomClient] Connecting to $ip:$port ...');
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _isConnected = true;

      _sub = _socket!.listen(
        (data) {
          _buffer.add(data);
          _processBuffer();
        },
        onDone: () {
          _isConnected = false;
          debugPrint('[RoomClient] Disconnected from $ip:$port');
          onDisconnected?.call();
        },
        onError: (error) {
          _isConnected = false;
          debugPrint('[RoomClient] Error: $error');
          onDisconnected?.call();
        },
      );
      debugPrint('[RoomClient] Connected to $ip:$port');
      return true;
    } catch (e, st) {
      _isConnected = false;
      debugPrint('[RoomClient] Connection FAILED to $ip:$port: $e\n$st');
      return false;
    }
  }

  /// 发送加入房间申请
  void sendJoin(String roomId, String deviceId, String deviceName) {
    _sendJson({
      'type': 'room_join',
      'roomId': roomId,
      'senderId': deviceId,
      'senderName': deviceName,
    });
  }

  /// 发送房间消息
  void sendMessage(RoomChatMessage msg) {
    debugPrint('[RoomClient] sendMessage: id=${msg.id} content=${msg.content}');
    _sendJson(msg.toRoomJson());
  }

  /// 发送离开房间
  void sendLeave(String roomId, String deviceId) {
    _sendJson({
      'type': 'room_leave',
      'roomId': roomId,
      'senderId': deviceId,
    });
  }

  /// 发送 JSON 数据('J' 标记 + TLV 格式)
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
      debugPrint('[RoomClient] Send error: $e\n$st');
    }
  }

  /// 处理接收缓冲(标记 + TLV,支持跨包拼接,分批让出事件循环)
  void _processBuffer() {
    final bytes = _buffer.takeBytes();
    var processed = 0;
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

      processed++;
      if (processed >= kMaxFramesPerBatch && bytes.length - consumed >= 5) {
        if (consumed < bytes.length) {
          _buffer.add(Uint8List.sublistView(bytes, consumed));
        }
        Timer.run(_processBuffer);
        return;
      }

      if (frameType != kJsonMarker) {
        debugPrint('[RoomClient] Ignore non-JSON frame');
        continue;
      }

      try {
        final json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
        _dispatch(json);
      } catch (e, st) {
        // 恶意/损坏帧:记录并跳过
        debugPrint('[RoomClient] frame parse error: $e\n$st');
      }
    }
    if (consumed < bytes.length) {
      _buffer.add(Uint8List.sublistView(bytes, consumed));
    }
  }

  /// 按帧类型分发
  void _dispatch(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    debugPrint('[RoomClient] frame: type=$type');
    switch (type) {
      case 'room_join_ack':
        final members = (json['members'] as List<dynamic>? ?? [])
            .map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
            .toList();
        onJoinAck?.call(
          json['roomId'] as String? ?? '',
          json['roomName'] as String? ?? '',
          json['hostId'] as String? ?? '',
          json['hostName'] as String? ?? '',
          members,
        );
        break;
      case 'room_join_reject':
        onJoinReject?.call(json['reason'] as String? ?? 'unknown');
        break;
      case 'room_members':
        final members = (json['members'] as List<dynamic>? ?? [])
            .map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
            .toList();
        onMembers?.call(
          json['action'] as String? ?? '',
          RoomMember.fromJson(json['member'] as Map<String, dynamic>? ?? {}),
          members,
        );
        break;
      case 'room_msg':
        onMessage?.call(RoomChatMessage.fromJson(json));
        break;
      case 'room_close':
        onRoomClose?.call();
        break;
      default:
        debugPrint('[RoomClient] Unknown frame type: $type');
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
