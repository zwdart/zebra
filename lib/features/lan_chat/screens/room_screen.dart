import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../models/room.dart';
import '../providers/lan_discovery_provider.dart';
import '../providers/room_provider.dart';
import '../services/lan_chat_settings.dart';
import '../widgets/message_bubble.dart';
import '../widgets/room_member_bar.dart';
import 'chat_screen.dart';
import '../../../widgets/custom_title_bar.dart';
import '../../../widgets/window_drag_region.dart';
import '../../../l10n/app_localizations.dart';

/// 聊天室会话页(房主与成员共用)
/// 房主模式:可解散房间;成员模式:可离开房间。
/// 房主离线/房间被解散时自动弹出并提示。
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final RoomProvider _provider;
  late List<ChatMessage> _messages;
  String _lastRoomId = '';
  StreamSubscription<ChatMessage>? _messageSub;
  bool _dissolveHandled = false; // 防止解散后重复弹提示/重复 pop
  String _lastMessagesSig = ''; // 消息列表签名,避免无关 notifyListeners 触发全量重建

  @override
  void initState() {
    super.initState();
    _provider = context.read<RoomProvider>();
    _lastRoomId = _provider.roomId ?? '';
    _messages = _provider.getMessages(_lastRoomId);
    if (_lastRoomId.isNotEmpty) _provider.markRead(_lastRoomId);
    _provider.addListener(_onProviderChanged);
    _messageSub = _provider.onMessageReceived.listen((msg) {
      if (!mounted) return;
      setState(() {
        _messages = _provider.getMessages(_provider.roomId ?? _lastRoomId);
      });
      _scrollToBottom();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _messageSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 房主离线/房间解散/主动离开后自动返回列表页;同时同步刷新消息列表。
  /// 自己发出的消息走 notifyListeners 通知(房主不会转回发送者,不经过
  /// onMessageReceived 流),必须在此处刷新才能立即上屏,否则要等远端
  /// 来消息触发流监听才一起显示。
  void _onProviderChanged() {
    if (!mounted || _dissolveHandled) return;
    if (_provider.role == RoomRole.none) {
      _dissolveHandled = true;
      final reason = _provider.dissolveReason;
      final loc = AppLocalizations.of(context);
      final message = reason == 'host_offline'
          ? loc.hostOffline
          : reason == 'room_close'
              ? loc.roomDissolved
              : null; // 主动离开不提示
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
        Navigator.of(context).maybePop();
      });
      return;
    }

    // 消息数量/最后一条变化才重建,避免成员数变化等通知触发全量重建
    final msgs = _provider.getMessages(_provider.roomId ?? _lastRoomId);
    final last = msgs.isEmpty ? null : msgs.last;
    final sig = last == null ? '0' : '${msgs.length}:${last.id}';
    if (sig == _lastMessagesSig) return;
    _lastMessagesSig = sig;
    setState(() {
      _messages = msgs;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final roomId = _provider.roomId;
    if (roomId == null) return;
    _provider.sendTextMessage(roomId, text);
    _textController.clear();
  }

  /// 房主解散/成员离开前的二次确认
  Future<void> _confirmExit() async {
    final loc = AppLocalizations.of(context);
    if (_provider.isHost) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.disbandRoom),
          content: Text(loc.confirmDisbandRoom),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.disbandRoom),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) _provider.disbandRoom();
    } else {
      _provider.leaveRoom();
    }
  }

  /// 成员详情弹窗:展示成员信息,提供「发消息」按钮进入单聊
  void _showMemberDetail(RoomMember member) {
    final loc = AppLocalizations.of(context);

    // 从发现服务中按 deviceId 匹配设备,拿到 IP/端口供单聊连接
    // (成员不在线时 ip 为空,ChatScreen 会显示"等待对方连接中"并自动重试)
    final discovery = context.read<LanDiscoveryProvider>();
    final devices = discovery.devices
        .where((d) => d.id == member.deviceId)
        .toList();
    final ip = devices.isNotEmpty ? devices.first.ip : '';
    final port = devices.isNotEmpty
        ? devices.first.port
        : LanChatSettings.defaultChatPort;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person, size: 20),
            const SizedBox(width: 8),
            Text(loc.memberDetails),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _memberInfoRow(ctx, Icons.person, loc.deviceName, member.deviceName),
            _memberInfoRow(ctx, Icons.tag, 'ID', member.deviceId),
            _memberInfoRow(
              ctx,
              Icons.lan,
              loc.ipAddress,
              ip.isEmpty ? '-' : ip,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.close),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.chat, size: 18),
            label: Text(loc.sendMessage),
            onPressed: () {
              Navigator.pop(ctx);
              if (!mounted) return;
              // 进入单聊:连接由 ChatScreen 自动处理(未在线时显示等待重连)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    peerId: member.deviceId,
                    peerName: member.deviceName,
                    peerIp: ip,
                    peerPort: port,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _memberInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('$label：', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(ColorScheme colorScheme) {
    final loc = AppLocalizations.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(Icons.groups, size: 18, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _provider.roomName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              Text(
                loc.roomMemberCountValue(_provider.memberCount),
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    final loc = AppLocalizations.of(context);
    return [
      Consumer<RoomProvider>(
        builder: (ctx, provider, _) {
          final isHost = provider.isHost;
          return PopupMenuButton<String>(
            tooltip: loc.more,
            onSelected: (value) {
              if (value == 'exit') _confirmExit();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'exit',
                child: ListTile(
                  leading: Icon(
                    isHost ? Icons.logout : Icons.exit_to_app,
                    size: 18,
                    color: isHost
                        ? Theme.of(ctx).colorScheme.error
                        : Theme.of(ctx).colorScheme.onSurface,
                  ),
                  title: Text(
                    isHost ? loc.disbandRoom : loc.leaveRoom,
                    style: TextStyle(
                      fontSize: 14,
                      color: isHost
                          ? Theme.of(ctx).colorScheme.error
                          : Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: CustomTitleBar.isDesktop
          ? null
          : WindowDragRegion(
              child: AppBar(
                titleSpacing: 8,
                title: _buildTitle(colorScheme),
                actions: _buildActions(),
              ),
            ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              titleWidget: _buildTitle(colorScheme),
              showBackButton: true,
              onBack: () => Navigator.of(context).maybePop(),
              actions: _buildActions(),
            ),
          // 成员横条(点击成员头像弹出详情,可发起私聊)
          Consumer<RoomProvider>(
            builder: (ctx, provider, _) => RoomMemberBar(
              members: provider.memberView,
              onMemberTap: (member) => _showMemberDetail(member),
            ),
          ),
          // 断线自动重连提示条(屏幕息屏/网络抖动时显示,房间并未解散)
          Consumer<RoomProvider>(
            builder: (ctx, provider, _) {
              if (!provider.isReconnecting) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: colorScheme.tertiaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        loc.reconnecting,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.groups,
                          size: 48,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          loc.noChatHistory,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    reverse: true,
                    itemBuilder: (ctx, i) {
                      final msg = _messages[_messages.length - 1 - i];
                      return MessageBubble(
                        message: msg,
                        peerId: 'room:$_lastRoomId',
                        onDelete: () {
                          // 复用 ChatRepository 删除房间消息(peer_id='room:<roomId>')
                          _provider.deleteRoomMessage(_lastRoomId, msg.id);
                          setState(() {
                            _messages = _provider.getMessages(_lastRoomId);
                          });
                        },
                      );
                    },
                  ),
          ),
          // 输入栏(聊天室内 v1 仅文本,不提供文件按钮)
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: loc.messageHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    maxLines: 4,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  tooltip: loc.send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
