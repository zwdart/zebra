import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/lan_device.dart';
import '../models/room.dart';
import '../models/room_chat_message.dart';
import '../repositories/chat_repository.dart';
import '../services/room_host.dart';
import '../services/room_client.dart';

/// 房间角色:无/房主/成员
enum RoomRole { none, host, member }

/// 房间状态管理(与 ChatProvider 平级,互不影响)
/// 房主侧:创建房间/接收成员/转发消息/解散;
/// 成员侧:加入房间/收发消息/离开;房主离线即解散。
class RoomProvider extends ChangeNotifier {
  final ChatRepository _repository = ChatRepository();
  final RoomHost _host = RoomHost();
  final RoomClient _client = RoomClient();
  final String _selfId;
  String _selfName;
  final void Function(RoomInfo) _onRoomInfoChanged; // 同步心跳 room 摘要
  final void Function() _onRoomInfoCleared; // 解散时清除心跳 room 摘要

  RoomRole _role = RoomRole.none;
  String? _roomId;
  String? _roomName;
  String? _hostName;
  List<RoomMember> _members = [];
  final List<RoomMember> _pendingMembers = []; // join_ack 前的占位(成员侧)
  bool _isConnected = false;
  String? _joinError; // 最近一次加入失败原因
  bool _isJoining = false; // 正在加入(UI 转圈)
  String? _dissolveReason; // 解散原因: room_close / host_offline / null(主动离开或解散)

  // ---- 断线自动重连(成员侧)----
  // 背景:屏幕息屏/网络抖动导致 TCP 断开时,房主和聊天室仍然在线,
  // 不能一断连就判定"房主离线、房间解散",否则息屏后回来房间已经没了。
  // 方案:断连后进入重连状态,周期性重连房主并重新 join;重连成功恢复,
  // 只有重试耗尽(房主真正离线)或收到 room_close/主动离开才解散。
  String? _hostIp; // 房主 IP(join 时记录,重连用)
  int _hostPort = 0; // 房主端口(join 时记录,重连用)
  bool _isReconnecting = false; // 断线自动重连中
  bool _manualDisconnect = false; // 主动离开/收到 room_close,不再重连
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0; // 已重试次数
  static const int _maxReconnectAttempts = 40; // 最多重试次数
  static const Duration _reconnectInterval = Duration(seconds: 3); // 重试间隔
  static const Duration _reconnectAckTimeout = Duration(seconds: 5); // 重连 join 的 ack 超时

  /// 消息流(新消息/系统消息通知 RoomScreen 刷新)
  final StreamController<ChatMessage> _messageController =
      StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onMessageReceived => _messageController.stream;

  RoomProvider({
    required String selfId,
    String? selfName,
    required void Function(RoomInfo) onRoomInfoChanged,
    required void Function() onRoomInfoCleared,
  })  : _selfId = selfId,
        _selfName = selfName ?? 'Unknown',
        _onRoomInfoChanged = onRoomInfoChanged,
        _onRoomInfoCleared = onRoomInfoCleared {
    _host.onMemberChanged = _handleHostMemberChanged;
    _host.onMessageReceived = _handleMessage;
    _host.onRoomClosed = _handleRoomClosed;
    _host.onLog = (log) => debugPrint('[RoomHost] $log');

    _client.onJoinAck = _handleJoinAck;
    _client.onJoinReject = _handleJoinReject;
    _client.onMembers = _handleMembers;
    _client.onMessage = _handleMessage;
    _client.onRoomClose = _handleRoomClose;
    _client.onDisconnected = _handleClientDisconnected;
    _client.onLog = (log) => debugPrint('[RoomClient] $log');
  }

  // ---------- 状态读取 ----------

  RoomRole get role => _role;
  bool get isHost => _role == RoomRole.host;
  bool get isMember => _role == RoomRole.member;
  bool get isConnected => _isConnected;
  bool get isJoining => _isJoining;
  bool get isReconnecting => _isReconnecting;
  String? get roomId => _roomId;
  String? get roomName => _roomName;
  String? get hostName => _hostName;
  String? get joinError => _joinError;
  String? get dissolveReason => _dissolveReason;
  String get selfId => _selfId;
  String get selfName => _selfName;
  List<RoomMember> get members => List.unmodifiable(_members);
  int get memberCount => _members.length;

  /// 成员侧 join 成功后显示的成员列表(含自己在内)
  List<RoomMember> get memberView =>
      isHost ? _members : _pendingMembers.isEmpty ? _members : _pendingMembers;

  /// 获取某个房间的历史消息(peer_id 以 "room:" 前缀标识房间)
  /// DB 查询为 timestamp DESC(最新在前),而 UI 渲染(reverse:true + 末尾索引)
  /// 期望旧→新顺序,故查询后反转,保证最新消息显示在底部。
  List<ChatMessage> getMessages(String roomId) {
    final msgs = _repository.getMessages('room:$roomId');
    return msgs.reversed.toList();
  }

  /// 更新用户名(房主时同步心跳摘要里的 hostName)
  void setSelfName(String name) {
    if (name.trim().isEmpty) return;
    _selfName = name.trim();
    if (isHost && _roomId != null) {
      _onRoomInfoChanged(RoomInfo(
        roomId: _roomId!,
        name: _roomName ?? '',
        hostName: _selfName,
        port: _host.port,
        memberCount: _host.memberCount,
      ));
    }
    notifyListeners();
  }

  // ---------- 创建/解散(房主侧) ----------

  /// 创建房间:启动 RoomHost,同步心跳摘要;成功返回 true
  Future<bool> createRoom(String name) async {
    final roomName = name.trim().isEmpty ? '我的房间' : name.trim();
    final roomId = const Uuid().v4();
    final port = await _host.start(
      roomId: roomId,
      roomName: roomName,
      hostId: _selfId,
      hostName: _selfName,
    );
    if (port <= 0) return false;

    _role = RoomRole.host;
    _roomId = roomId;
    _roomName = roomName;
    _hostName = _selfName;
    _members = [
      RoomMember(deviceId: _selfId, deviceName: _selfName),
    ];
    _isConnected = true;
    _joinError = null;
    _onRoomInfoChanged(RoomInfo(
      roomId: roomId,
      name: roomName,
      hostName: _selfName,
      port: port,
      memberCount: 1,
    ));
    notifyListeners();
    debugPrint('[RoomProvider] Room created: $roomName($roomId) port=$port');
    return true;
  }

  /// 解散房间(仅房主):广播 room_close,停止服务器,清除心跳摘要
  void disbandRoom() {
    if (!isHost) return;
    _host.close();
    _onRoomInfoCleared();
    _resetState();
    notifyListeners();
  }

  // ---------- 加入/离开(成员侧) ----------

  /// 加入房间:连接房主并发送 room_join;结果通过回调/状态反馈
  Future<void> joinRoom(LanDevice host) async {
    final info = host.roomInfo;
    if (info == null || _isJoining) return;
    _isJoining = true;
    _joinError = null;
    _isConnected = false;
    // 记录房主地址,断线自动重连时使用
    _hostIp = host.ip;
    _hostPort = info.port;
    notifyListeners();

    final ok = await _client.connect(host.ip, info.port);
    if (!ok) {
      _isJoining = false;
      _joinError = '无法连接房主,请确认房主在线';
      debugPrint('[RoomProvider] join failed: connect error');
      notifyListeners();
      return;
    }
    _client.sendJoin(info.roomId, _selfId, _selfName);
    // 连接建立但尚未 ack 期间保持 joining 状态(ack/reject 回调里收尾)
  }

  /// 离开房间(仅成员):发送 room_leave 并断开
  void leaveRoom() {
    if (!isMember) return;
    _manualDisconnect = true;
    _stopReconnect();
    if (_roomId != null && _isConnected) {
      _client.sendLeave(_roomId!, _selfId);
    }
    _client.disconnect();
    _resetState();
    notifyListeners();
  }

  /// 发送文本消息(房主与成员共用)
  void sendTextMessage(String roomId, String text) {
    if (text.trim().isEmpty) return;
    final msg = RoomChatMessage(
      roomId: roomId,
      id: const Uuid().v4(),
      senderId: _selfId,
      senderName: _selfName,
      type: MessageType.text,
      content: text.trim(),
      timestamp: DateTime.now(),
      isMe: true,
      sendStatus: SendStatus.sending,
    );
    _saveMessage(msg, roomId);
    notifyListeners();

    if (isHost) {
      // 房主直接广播(不经过 socket)
      _host.sendMessage(msg);
    } else {
      _client.sendMessage(msg);
    }
  }

  /// 删除房间内的单条消息(复用 ChatRepository,peer_id 以 "room:" 前缀标识房间)
  void deleteRoomMessage(String roomId, String msgId) {
    _repository.deleteMessagesByIds('room:$roomId', [msgId]);
    notifyListeners();
  }

  // ---------- 回调处理 ----------

  /// 房主侧:成员加入/离开 → 更新成员表 + 系统消息广播
  void _handleHostMemberChanged(
      String action, RoomMember member, List<RoomMember> members) {
    _members = List.of(members);
    if (_roomId != null) {
      // 同步心跳摘要里的成员数
      _onRoomInfoChanged(RoomInfo(
        roomId: _roomId!,
        name: _roomName ?? '',
        hostName: _selfName,
        port: _host.port,
        memberCount: _members.length,
      ));
    }
    _addSystemMessage(action == 'joined' ? '${member.deviceName} 加入了房间' : '${member.deviceName} 离开了房间');
    notifyListeners();
  }

  /// 成员侧:join 成功
  void _handleJoinAck(String roomId, String roomName, String hostId,
      String hostName, List<RoomMember> members) {
    _role = RoomRole.member;
    _roomId = roomId;
    _roomName = roomName;
    _hostName = hostName;
    // 成员列表需包含自己(房主返回的 members 已含自己,若没有则补上)
    _members = List.of(members);
    if (!_members.any((m) => m.deviceId == _selfId)) {
      _members = [
        ..._members,
        RoomMember(deviceId: _selfId, deviceName: _selfName),
      ];
    }
    _pendingMembers.clear();
    _isConnected = true;
    _isJoining = false;
    _joinError = null;
    // 重连成功:退出重连状态,恢复消息收发
    if (_isReconnecting) {
      _isReconnecting = false;
      _reconnectAttempts = 0;
      debugPrint('[RoomProvider] Reconnected to room: $roomName($roomId)');
    }
    notifyListeners();
    debugPrint('[RoomProvider] Joined room: $roomName($roomId)');
  }

  /// 成员侧:join 被拒
  void _handleJoinReject(String reason) {
    // 重连被拒(房间已满/不存在/已解散):停止重连,按房间解散处理
    if (_isReconnecting) {
      _stopReconnect();
      _client.disconnect();
      _dissolveReason = 'host_offline';
      _resetState();
      notifyListeners();
      return;
    }
    _isJoining = false;
    _isConnected = false;
    _joinError = reason == 'full' ? '房间人数已满' : '房间不存在或已解散';
    _client.disconnect();
    notifyListeners();
  }

  /// 成员侧:成员变化广播 → 更新成员表 + 系统消息
  void _handleMembers(
      String action, RoomMember member, List<RoomMember> members) {
    _members = List.of(members);
    if (!_members.any((m) => m.deviceId == _selfId)) {
      _members = [
        ..._members,
        RoomMember(deviceId: _selfId, deviceName: _selfName),
      ];
    }
    _addSystemMessage(action == 'joined' ? '${member.deviceName} 加入了房间' : '${member.deviceName} 离开了房间');
    notifyListeners();
  }

  /// 收到房间消息(房主转发/成员直收),按 msgId 去重
  void _handleMessage(RoomChatMessage msg) {
    if (msg.roomId != _roomId) return;
    final key = msg.id;
    // 本地已发送的消息(自己发的那条)不重复上屏
    final exists = _repositoryExists(key, msg.roomId);
    if (exists) return;
    _saveMessage(msg.copyWith(isMe: msg.senderId == _selfId), msg.roomId);
    _messageController.add(msg);
    notifyListeners();
  }

  /// 房主侧房间被关闭(close 触发,当前只发生在主动解散)
  void _handleRoomClosed() {
    _resetState();
    notifyListeners();
  }

  /// 成员侧:房主广播 room_close → 房间解散
  void _handleRoomClose() {
    debugPrint('[RoomProvider] Room closed by host');
    _manualDisconnect = true;
    _stopReconnect();
    _dissolveReason = 'room_close';
    _client.disconnect();
    _resetState();
    _joinError = null;
    notifyListeners();
  }

  /// 成员侧:与房主连接断开。
  /// 屏幕息屏/网络抖动导致的暂时断连不能直接解散房间(房主可能仍在线),
  /// 先进入自动重连;重试耗尽(房主真正离线)才按 host_offline 解散。
  void _handleClientDisconnected() {
    if (!isMember || _manualDisconnect) return;
    debugPrint('[RoomProvider] Host connection lost, start auto-reconnect');
    _isConnected = false;
    _isJoining = false;
    if (_isReconnecting) return; // 已在重连中
    _isReconnecting = true;
    _reconnectAttempts = 0;
    notifyListeners();
    _scheduleReconnect();
  }

  // ---------- 内部工具 ----------

  /// 调度下一次重连尝试
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, _tryReconnect);
  }

  /// 执行一次重连:重新连接房主并发送 join;
  /// 成功由 _handleJoinAck 收尾,失败继续调度,超时按失败处理。
  Future<void> _tryReconnect() async {
    if (!isMember || !_isReconnecting) return;
    final ip = _hostIp;
    final port = _hostPort;
    final roomId = _roomId;
    if (ip == null || port <= 0 || roomId == null) {
      _failReconnect();
      return;
    }
    _reconnectAttempts++;
    debugPrint(
      '[RoomProvider] Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts -> $ip:$port',
    );
    final ok = await _client.connect(ip, port);
    if (!ok) {
      _onReconnectFailed();
      return;
    }
    // 连接成功,发送 join;等待 ack/reject 回调。
    // 若超时未收到 ack(房主无响应/连接被静默丢弃),按失败继续重试。
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectAckTimeout, () {
      debugPrint('[RoomProvider] Reconnect join ack timeout, retry later');
      _client.disconnect();
      _onReconnectFailed();
    });
    _client.sendJoin(roomId, _selfId, _selfName);
  }

  /// 单次重连失败:未达上限则继续调度,否则判定房主离线并解散
  void _onReconnectFailed() {
    if (!_isReconnecting) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _failReconnect();
      return;
    }
    _scheduleReconnect();
  }

  /// 重连彻底失败(房主真正离线):停止重连,按 host_offline 解散房间
  void _failReconnect() {
    if (!_isReconnecting) return;
    debugPrint('[RoomProvider] Reconnect exhausted, room dissolved (host offline)');
    _stopReconnect();
    _client.disconnect();
    _dissolveReason = 'host_offline';
    _resetState();
    notifyListeners();
  }

  /// 停止重连(主动离开/收到 room_close/解散时调用)
  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectAttempts = 0;
  }

  /// 检查某消息 id 是否已存在于房间历史(去重用)
  bool _repositoryExists(String msgId, String roomId) {
    return getMessages(roomId).any((m) => m.id == msgId);
  }

  /// 保存消息到内存与数据库(peer_id 以 "room:" 前缀标识房间)
  /// 会话列表显示名用房间名,避免聊天记录里显示成最后一个发言者的昵称
  void _saveMessage(ChatMessage msg, String roomId) {
    _repository.saveMessage(
      msg,
      'room:$roomId',
      peerName: _roomName ?? _hostName ?? '',
    );
  }

  /// 标记房间消息已读(进入聊天室页时调用)
  void markRead(String roomId) {
    _repository.markRead('room:$roomId');
    notifyListeners();
  }

  /// 生成系统消息(成员进出),仅本地显示不广播
  void _addSystemMessage(String content) {
    if (_roomId == null) return;
    final msg = RoomChatMessage(
      roomId: _roomId!,
      id: const Uuid().v4(),
      senderId: 'system',
      senderName: '',
      type: MessageType.system,
      content: content,
      timestamp: DateTime.now(),
      isMe: false,
    );
    _saveMessage(msg, _roomId!);
    _messageController.add(msg);
  }

  /// 重置全部状态(离开/解散/断开)
  void _resetState() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _role = RoomRole.none;
    _roomId = null;
    _roomName = null;
    _hostName = null;
    _members = [];
    _pendingMembers.clear();
    _isConnected = false;
    _isJoining = false;
    _isReconnecting = false;
    _reconnectAttempts = 0;
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _client.dispose();
    _host.stop();
    _messageController.close();
    super.dispose();
  }
}
