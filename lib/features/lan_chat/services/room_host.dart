import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/room.dart';
import '../models/room_chat_message.dart';

/// 帧类型标记('J' JSON 帧,与单聊一致)
const int kJsonMarker = 0x4A;

/// 单批最多同步解析的帧数,超过后让出事件循环(Timer.run)分批继续,
/// 避免转发高峰时主 isolate 被占满导致 UI 卡死(与单聊约定一致)。
const int kMaxFramesPerBatch = 16;

/// 房间人数上限(默认,可配)
const int kMaxRoomMembers = 50;

/// 单条房间消息内容大小上限(防恶意大帧刷爆房主转发)
const int kMaxRoomMessageBytes = 64 * 1024;

/// 默认房间端口(与单聊 22066 错开;被占用时走候选端口策略)
const int kDefaultRoomPort = 22088;

/// 房间成员变化回调(action: joined/left;members 为变化后的全量列表)
typedef OnRoomMemberChanged = void Function(
    String action, RoomMember member, List<RoomMember> members);

/// 房间消息回调(房主收到并转发的消息)
typedef OnRoomMessageReceived = void Function(RoomChatMessage message);

/// 房间解散回调
typedef OnRoomClosed = void Function();

/// 日志回调
typedef OnLog = void Function(String log);

/// 已连接的房间成员连接信息
class _RoomPeer {
  final Socket socket;
  final String ip;
  StreamSubscription<Uint8List>? sub; // socket 数据订阅
  String? deviceId;
  String? deviceName;
  int msgLen = -1; // 当前帧数据长度,跨 TCP 包保持
  int? frameType; // 当前帧类型

  _RoomPeer({required this.socket, required this.ip});
}

/// 房主房间服务器(方案 A 星型拓扑的中心)
/// 监听独立端口,接收成员连接;维护成员表(权威版本),转发房间消息。
/// 与单聊 ChatServer 完全独立,互不影响。
class RoomHost {
  ServerSocket? _serverSocket;
  bool _isRunning = false;
  String? _roomId;
  String? _roomName;
  String? _hostId;
  String? _hostName;
  final List<_RoomPeer> _pendingPeers = []; // 尚未完成 join 的连接
  final Map<String, _RoomPeer> _members = {}; // deviceId -> peer

  OnRoomMemberChanged? onMemberChanged;
  OnRoomMessageReceived? onMessageReceived;
  OnRoomClosed? onRoomClosed;
  OnLog? onLog;

  int get port => _serverSocket?.port ?? 0;
  bool get isRunning => _isRunning;
  String? get roomId => _roomId;
  String? get roomName => _roomName;

  /// 当前成员列表(全量,按加入顺序)
  List<RoomMember> get members => [
        for (final p in _members.values)
          RoomMember(deviceId: p.deviceId!, deviceName: p.deviceName ?? ''),
      ];

  int get memberCount => _members.length;

  /// 候选端口数量:默认端口被占用时依次尝试后续连续端口
  static const int _portCandidateCount = 20;

  /// 启动房间服务器
  Future<int> start({
    required String roomId,
    required String roomName,
    required String hostId,
    required String hostName,
    int port = kDefaultRoomPort,
  }) async {
    if (_isRunning) return this.port;
    _roomId = roomId;
    _roomName = roomName;
    _hostId = hostId;
    _hostName = hostName;

    for (var candidate = port; candidate < port + _portCandidateCount; candidate++) {
      try {
        return await _bindAndListen(candidate);
      } catch (e) {
        debugPrint('[RoomHost] Bind port $candidate failed: $e');
      }
    }
    debugPrint(
        '[RoomHost] Ports $port-${port + _portCandidateCount - 1} all occupied, fallback to random port');
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
        debugPrint('[RoomHost] Error: $error');
      },
    );
    debugPrint('[RoomHost] Listening on port ${_serverSocket!.port} (room=$_roomId)');
    return _serverSocket!.port;
  }

  /// 停止房间服务器(不广播 close,由调用方决定是否先广播)
  void stop() {
    _isRunning = false;
    _roomId = null;
    _roomName = null;
    for (final peer in _members.values) {
      peer.socket.close();
    }
    _members.clear();
    for (final peer in _pendingPeers) {
      peer.socket.close();
    }
    _pendingPeers.clear();
    _serverSocket?.close();
    _serverSocket = null;
    debugPrint('[RoomHost] Stopped');
  }

  /// 房主解散房间:广播 room_close 后停止服务器
  void close() {
    if (!_isRunning) return;
    for (final peer in _members.values) {
      _sendJson(peer.socket, {'type': 'room_close', 'roomId': _roomId});
    }
    stop();
    onRoomClosed?.call();
  }

  /// 房主自己发言:广播给所有成员(与成员消息走同一转发路径)
  bool sendMessage(RoomChatMessage msg) {
    if (!_isRunning || msg.roomId != _roomId) return false;
    for (final peer in _members.values) {
      _sendJson(peer.socket, msg.toRoomJson());
    }
    onMessageReceived?.call(msg);
    return true;
  }

  /// 处理客户端连接
  void _handleClient(Socket client) {
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    final remoteAddr = '${client.remoteAddress.address}:${client.remotePort}';
    debugPrint('[RoomHost] Client connected: $remoteAddr');

    final peer = _RoomPeer(socket: client, ip: client.remoteAddress.address);
    _pendingPeers.add(peer);

    // 每个客户端独立的接收缓冲(BytesBuilder 低拷贝累积)
    final buffer = BytesBuilder(copy: false);

    peer.sub = client.listen(
      (data) {
        buffer.add(data);
        _processBuffer(client, buffer, peer);
      },
      onDone: () {
        debugPrint('[RoomHost] Client disconnected: $remoteAddr');
        _removePeer(peer);
      },
      onError: (error) {
        debugPrint('[RoomHost] Client error: $error');
        _removePeer(peer);
      },
    );
  }

  /// 处理缓冲区中的数据(标记 + TLV 格式,支持跨包解析,分批让出事件循环)
  void _processBuffer(Socket client, BytesBuilder buffer, _RoomPeer peer) {
    final bytes = buffer.takeBytes();
    var processed = 0;
    var consumed = 0;
    while (true) {
      if (peer.frameType == null) {
        if (bytes.length - consumed < 5) break; // 1 标记 + 4 长度
        peer.frameType = bytes[consumed];
        peer.msgLen = (bytes[consumed + 1] << 24) |
            (bytes[consumed + 2] << 16) |
            (bytes[consumed + 3] << 8) |
            bytes[consumed + 4];
        consumed += 5;
      }

      if (bytes.length - consumed < peer.msgLen) break;

      final chunk = Uint8List.sublistView(bytes, consumed, consumed + peer.msgLen);
      consumed += peer.msgLen;
      final frameType = peer.frameType!;
      peer.msgLen = -1;
      peer.frameType = null;

      processed++;
      if (processed >= kMaxFramesPerBatch && bytes.length - consumed >= 5) {
        if (consumed < bytes.length) {
          buffer.add(Uint8List.sublistView(bytes, consumed));
        }
        Timer.run(() => _processBuffer(client, buffer, peer));
        return;
      }

      if (frameType != kJsonMarker) {
        // 非 JSON 帧(如单聊 'G' 文件块):房间通道不支持,跳过
        debugPrint('[RoomHost] Ignore non-JSON frame: ${String.fromCharCode(frameType)}');
        continue;
      }

      try {
        final json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
        _dispatch(peer, json);
      } catch (e, st) {
        // 恶意/损坏帧:记录并跳过,不能因此取消 socket 监听
        debugPrint('[RoomHost] frame parse error: $e\n$st');
      }
    }
    if (consumed < bytes.length) {
      buffer.add(Uint8List.sublistView(bytes, consumed));
    }
  }

  /// 按帧类型分发
  void _dispatch(_RoomPeer peer, Map<String, dynamic> json) {
    switch (json['type']) {
      case 'room_join':
        _handleJoin(peer, json);
        break;
      case 'room_leave':
        _handleLeave(peer, json);
        break;
      case 'room_msg':
        _handleRoomMsg(peer, json);
        break;
      default:
        debugPrint('[RoomHost] Unknown frame type: ${json['type']}');
    }
  }

  /// 成员申请加入:校验房间/人数上限,回复 ack/reject,并广播成员变化
  void _handleJoin(_RoomPeer peer, Map<String, dynamic> json) {
    final rid = json['roomId'] as String?;
    if (rid != _roomId) {
      _sendJson(peer.socket,
          {'type': 'room_join_reject', 'roomId': rid ?? '', 'reason': 'not_found'});
      debugPrint('[RoomHost] Reject join: roomId mismatch ($rid != $_roomId)');
      return;
    }
    final deviceId = json['senderId'] as String? ?? '';
    final deviceName = json['senderName'] as String? ?? '';
    if (deviceId.isEmpty) {
      debugPrint('[RoomHost] Reject join: empty deviceId');
      return;
    }

    // 重复加入(重连场景):先关闭旧连接,以新连接为准
    final existing = _members[deviceId];
    if (existing != null && !identical(existing, peer)) {
      debugPrint('[RoomHost] Re-join: close old connection of $deviceId');
      existing.socket.close();
      _members.remove(deviceId);
      _pendingPeers.remove(existing);
    }

    if (!_members.containsKey(deviceId) && _members.length >= kMaxRoomMembers) {
      _sendJson(peer.socket,
          {'type': 'room_join_reject', 'roomId': rid, 'reason': 'full'});
      debugPrint('[RoomHost] Reject join: room full ($deviceId)');
      return;
    }

    peer.deviceId = deviceId;
    peer.deviceName = deviceName;
    _pendingPeers.remove(peer);
    _members[deviceId] = peer;

    // ack:含房间信息与全量成员列表
    _sendJson(peer.socket, {
      'type': 'room_join_ack',
      'roomId': _roomId,
      'roomName': _roomName,
      'hostId': _hostId,
      'hostName': _hostName,
      'members': _membersJson(),
    });
    debugPrint('[RoomHost] $deviceName($deviceId) joined');

    // 广播成员变化(其他成员 + 上层)
    final member = RoomMember(deviceId: deviceId, deviceName: deviceName);
    _broadcastMembers('joined', member);
    onMemberChanged?.call('joined', member, members);
  }

  /// 成员主动离开
  void _handleLeave(_RoomPeer peer, Map<String, dynamic> json) {
    final deviceId = peer.deviceId ?? json['senderId'] as String?;
    if (deviceId == null) return;
    final removed = _members.remove(deviceId);
    _pendingPeers.remove(peer);
    if (removed != null) {
      final member = RoomMember(deviceId: deviceId, deviceName: peer.deviceName ?? '');
      _broadcastMembers('left', member);
      onMemberChanged?.call('left', member, members);
      debugPrint('[RoomHost] $deviceId left');
    }
    peer.socket.close();
  }

  /// 成员发来的房间消息:校验身份后转发给其他所有成员(原样转发,msgId 全局一致)
  void _handleRoomMsg(_RoomPeer peer, Map<String, dynamic> json) {
    if (peer.deviceId == null) return; // 未完成 join 的连接不处理
    final msg = RoomChatMessage.fromJson(json);
    if (msg.roomId != _roomId) return;
    if (msg.id.isEmpty) return;
    // 防伪冒:转发前校验 senderId 与连接身份一致
    if (msg.senderId != peer.deviceId) {
      debugPrint('[RoomHost] Drop forged room_msg: sender=${msg.senderId} conn=${peer.deviceId}');
      return;
    }
    // 防恶意大帧
    if (utf8.encode(msg.content).length > kMaxRoomMessageBytes) {
      debugPrint('[RoomHost] Drop oversized room_msg from ${peer.deviceId}');
      return;
    }

    for (final entry in _members.entries) {
      if (entry.key == peer.deviceId) continue; // 不转回发送者
      _sendJson(entry.value.socket, msg.toRoomJson());
    }
    onMessageReceived?.call(msg);
  }

  /// 广播成员变化(增量 member + 全量列表,便于成员端自愈同步)
  void _broadcastMembers(String action, RoomMember member) {
    for (final peer in _members.values) {
      _sendJson(peer.socket, {
        'type': 'room_members',
        'roomId': _roomId,
        'action': action,
        'member': member.toJson(),
        'members': _membersJson(),
      });
    }
  }

  /// 全量成员列表 JSON
  List<Map<String, dynamic>> _membersJson() => [
        for (final p in _members.values)
          {'deviceId': p.deviceId, 'deviceName': p.deviceName ?? ''},
      ];

  /// 连接断开/出错时移除成员并广播(仅当该连接仍映射到成员表时)
  void _removePeer(_RoomPeer peer) {
    _pendingPeers.remove(peer);
    final id = peer.deviceId;
    if (id != null && identical(_members[id], peer)) {
      _members.remove(id);
      final member = RoomMember(deviceId: id, deviceName: peer.deviceName ?? '');
      _broadcastMembers('left', member);
      onMemberChanged?.call('left', member, members);
      debugPrint('[RoomHost] Peer disconnected: $id');
    }
  }

  /// 发送 JSON 数据('J' 标记 + TLV 格式)
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
      debugPrint('[RoomHost] Send error: $e\n$st');
      return false;
    }
  }
}
