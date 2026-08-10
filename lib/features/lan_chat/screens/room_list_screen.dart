import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lan_device.dart';
import '../providers/lan_discovery_provider.dart';
import '../providers/room_provider.dart';
import '../widgets/room_tile.dart';
import 'room_screen.dart';
import '../../../l10n/app_localizations.dart';

/// 聊天室列表页(作为首页第三 Tab 嵌入,不自带 Scaffold/AppBar):
/// 我的房间(创建/进入/解散) + 附近房间(心跳发现的房间摘要)
class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  bool _navigated = false; // 防止加入/创建成功后重复跳转
  RoomRole? _lastRole; // 上次 build 时的角色,用于检测"刚从 none 变为 host/member"的瞬间
  String? _lastJoinError; // 已提示过的加入错误,避免重复弹窗

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Consumer<RoomProvider>(
      builder: (ctx, provider, _) {
        _handleJoinResult(ctx, provider);
        final role = provider.role;
        // 仅在角色从 none 变为 host/member 的那一次 build 触发自动进入,
        // 之后返回列表页不会再自动跳转(避免"返回又跳"的循环)。
        // 通过 _lastRole 检测状态迁移,而不是"只要 role != none 就跳"。
        if (role != RoomRole.none &&
            _lastRole == RoomRole.none &&
            !_navigated) {
          _navigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoomScreen()),
            ).then((_) {
              _navigated = false;
            });
          });
        }
        _lastRole = role;
        return RefreshIndicator(
          onRefresh: () async {
            final discovery = context.read<LanDiscoveryProvider>();
            discovery.stop();
            await discovery.start();
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ---- 我的房间 ----
              _sectionHeader(loc.myRoom),
              _buildMyRoomCard(ctx, provider),
              const SizedBox(height: 8),
              // ---- 附近房间 ----
              _sectionHeader(loc.nearbyRooms),
              _buildNearbyRooms(ctx),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  /// 我的房间卡片:未建房显示创建按钮;已建房显示房间信息
  Widget _buildMyRoomCard(BuildContext context, RoomProvider provider) {
    final loc = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (provider.role == RoomRole.none) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(Icons.add, color: colorScheme.onPrimaryContainer),
          ),
          title: Text(
            loc.createRoom,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            loc.roomNameHint,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          trailing: FilledButton.tonal(
            onPressed: () => _showCreateRoomDialog(context, provider),
            child: Text(loc.createRoom),
          ),
          onTap: () => _showCreateRoomDialog(context, provider),
        ),
      );
    }

    // 已建房/已加入(回到本页的场景,如从聊天室返回)
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(Icons.groups, color: colorScheme.onPrimaryContainer),
        ),
        // 长房名省略号,避免换行撑高卡片/挤压右侧按钮
        title: Text(
          provider.roomName ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          loc.roomMemberCountValue(provider.memberCount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        // trailing 紧凑化:手机上让出更多空间给房名
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider.isHost)
              IconButton(
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                tooltip: loc.disbandRoom,
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDisband(context, provider),
              ),
            // 成员状态下允许创建自己的房间:确认离开当前聊天室后进入创建流程
            if (!provider.isHost) ...[
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: loc.createRoom,
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmCreateOwnRoom(context, provider),
              ),
              const SizedBox(width: 4),
            ],
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RoomScreen()),
                );
              },
              child: Text(loc.enterRoom),
            ),
          ],
        ),
      ),
    );
  }

  /// 附近房间:发现设备中带 room 摘要的条目
  Widget _buildNearbyRooms(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final discovery = context.watch<LanDiscoveryProvider>();

    if (!discovery.isRunning) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            loc.enableDiscoveryHint,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final rooms = discovery.devices.where((d) => d.roomInfo != null).toList();
    if (rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            loc.noRoomsFound,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final device in rooms)
          RoomTile(
            device: device,
            onJoin: () => _joinRoom(context, device),
          ),
      ],
    );
  }

  /// 创建房间对话框
  Future<void> _showCreateRoomDialog(
      BuildContext context, RoomProvider provider) async {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: '${loc.roomNameDefault}-${provider.selfName}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.createRoom),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: loc.roomNameHint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: Text(loc.createRoom),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final ok = await provider.createRoom(name);
    if (ok) {
      // 状态变化后由 build 中的监听跳转 RoomScreen
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.cannotConnectHost)),
      );
    }
  }

  /// 解散房间确认
  Future<void> _confirmDisband(
      BuildContext context, RoomProvider provider) async {
    final loc = AppLocalizations.of(context);
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
    if (confirmed == true && mounted) provider.disbandRoom();
  }

  /// 成员状态下创建自己的房间:先确认离开当前聊天室,再进入创建流程。
  /// (单角色模型:同一时间只能在一个房间,创建前必须先 leaveRoom)
  Future<void> _confirmCreateOwnRoom(
      BuildContext context, RoomProvider provider) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.createRoom),
        content: Text(loc.createRoomLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.createRoom),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    provider.leaveRoom(); // 离开当前聊天室(role → none)
    _showCreateRoomDialog(context, provider);
  }

  /// 加入房间:已在该房间时直接进入;已在其他房间时先确认离开再切换
  Future<void> _joinRoom(BuildContext context, LanDevice device) async {
    final provider = context.read<RoomProvider>();
    final loc = AppLocalizations.of(context);
    final targetRoomId = device.roomInfo?.roomId;

    // 已是房主:不能直接加入其他房间(房主解散会波及所有成员),提示先解散
    if (provider.isHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.hostJoinOthersHint)),
      );
      return;
    }

    // 已加入该房间:直接进入聊天室,不再重复加入
    if (provider.isMember &&
        provider.roomId != null &&
        targetRoomId != null &&
        provider.roomId == targetRoomId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RoomScreen()),
      );
      return;
    }

    // 已是其他房间的成员:确认离开当前聊天室后再加入
    if (provider.isMember) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.joinRoom),
          content: Text(loc.joinRoomLeaveConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.joinRoom),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      provider.leaveRoom(); // 离开当前聊天室(role → none)
    }

    provider.joinRoom(device);
  }

  /// 加入结果处理:失败时一次性提示
  void _handleJoinResult(BuildContext context, RoomProvider provider) {
    if (provider.isJoining) return;
    final error = provider.joinError;
    if (error == null || error == _lastJoinError) return;
    _lastJoinError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    });
  }
}
