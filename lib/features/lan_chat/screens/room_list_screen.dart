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
        title: Text(
          provider.roomName ?? '',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          loc.roomMemberCountValue(provider.memberCount),
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider.isHost)
              IconButton(
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                tooltip: loc.disbandRoom,
                onPressed: () => _confirmDisband(context, provider),
              ),
            const SizedBox(width: 4),
            FilledButton.tonal(
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

  /// 加入房间:调 RoomProvider.joinRoom,结果通过 joinError/状态反馈
  void _joinRoom(BuildContext context, LanDevice device) {
    final provider = context.read<RoomProvider>();
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
