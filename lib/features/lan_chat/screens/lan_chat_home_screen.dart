import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lan_device.dart';
import '../providers/lan_discovery_provider.dart';
import '../providers/chat_provider.dart';
import '../repositories/chat_repository.dart';
import '../services/lan_chat_settings.dart';
import '../widgets/device_tile.dart';
import '../../../widgets/custom_title_bar.dart';
import '../../../widgets/window_drag_region.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/relative_time.dart';
import 'chat_screen.dart';
import 'room_list_screen.dart';

/// 本地聊天首页：设备列表 + 会话列表
class LanChatHomeScreen extends StatefulWidget {
  /// 作为主 Tab 嵌入 shell 时无需返回(默认);从设置页 push 进入时才需要
  final bool showBackButton;

  const LanChatHomeScreen({super.key, this.showBackButton = false});

  @override
  State<LanChatHomeScreen> createState() => _LanChatHomeScreenState();
}

class _LanChatHomeScreenState extends State<LanChatHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ChatRepository _repository = ChatRepository();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 发现端口非默认时,进入首页弹一次提醒(每天最多一次)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDiscoveryPortWarning());
  }

  /// 发现端口非默认时,每天提醒一次:可能无法正常搜索到其他客户端,并提供一键重置
  Future<void> _checkDiscoveryPortWarning() async {
    final configured = await LanChatSettings.getDiscoveryPort();
    if (configured == null || configured == LanChatSettings.defaultDiscoveryPort) {
      return;
    }
    if (await LanChatSettings.isWarningShownToday()) return;
    await LanChatSettings.markWarningShownToday();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).discoveryPortNonDefault),
        content: Text(
          AppLocalizations.of(ctx).discoveryPortWarningValue(
            configured,
            LanChatSettings.defaultDiscoveryPort,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).gotIt),
          ),
          FilledButton(
            onPressed: () => _resetDiscoveryPort(ctx),
            child: Text(AppLocalizations.of(ctx).resetNow),
          ),
        ],
      ),
    );
  }

  /// 一键重置:恢复默认发现端口并重启发现服务
  Future<void> _resetDiscoveryPort(BuildContext dialogContext) async {
    final provider = context.read<LanDiscoveryProvider>();
    await LanChatSettings.setDiscoveryPort(null);
    if (provider.isRunning) {
      provider.stop();
      await provider.start();
    }
    if (!dialogContext.mounted) return;
    Navigator.pop(dialogContext);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).discoveryPortReset)),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _connectToDevice(LanDevice device) {
    debugPrint(
      '[LanChatHome] connectToDevice: ${device.name} ${device.ip}:${device.port} online=${device.isOnline}',
    );
    // 立即进入聊天页,由聊天页负责自动连接:
    // 连接中显示"正在连接中",失败后显示"等待对方连接中"并自动重试,
    // 不再在跳转前阻塞等待 TCP 连接或弹出失败提示
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerId: device.id,
          peerName: device.name,
          peerIp: device.ip,
          peerPort: device.port,
        ),
      ),
    );
  }

  /// 确认后从设备列表中删除离线残留设备
  Future<void> _confirmRemoveDevice(
    BuildContext context,
    LanDiscoveryProvider provider,
    LanDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).deleteDevice),
        content: Text(
          AppLocalizations.of(ctx)
              .confirmDeleteDeviceValue(device.name, '${device.ip}:${device.port}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx).delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    provider.removeDevice(device.ip, device.port);
  }

  /// 获取本机局域网 IP 地址
  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        if (iface.name.startsWith('lo') ||
            iface.name.startsWith('docker') ||
            iface.name.startsWith('veth'))
          continue;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  void _showLocalInfo(BuildContext context) async {
    final chatProvider = context.read<ChatProvider>();
    final discoveryProvider = context.read<LanDiscoveryProvider>();
    final ip = await _getLocalIp();
    final port = chatProvider.tcpPort;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(ctx).localInfo),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow(Icons.lan, AppLocalizations.of(ctx).localInfoIp, ip),
            const SizedBox(height: 12),
            _infoRow(
              Icons.settings_ethernet,
              AppLocalizations.of(ctx).localInfoPort,
              '$port',
            ),
            const SizedBox(height: 12),
            _infoRow(
              Icons.person,
              AppLocalizations.of(ctx).localInfoDeviceName,
              chatProvider.selfName,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit, size: 16),
            label: Text(AppLocalizations.of(ctx).editNickname),
            onPressed: () {
              Navigator.pop(ctx);
              _editNickname(context, chatProvider, discoveryProvider);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).close),
          ),
        ],
      ),
    );
  }

  void _editNickname(
    BuildContext context,
    ChatProvider chatProvider,
    LanDiscoveryProvider discoveryProvider,
  ) {
    final controller = TextEditingController(text: chatProvider.selfName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).changeNickname),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(ctx).nicknameHint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 20,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(ctx).nicknameNotEmpty)),
                );
                return;
              }
              chatProvider.setSelfName(name);
              discoveryProvider.setDeviceName(name);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(ctx).nicknameUpdatedValue(name)),
                ),
              );
            },
            child: Text(AppLocalizations.of(ctx).save),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text('$label：', style: const TextStyle(fontSize: 13)),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;
    return Scaffold(
      appBar: isDesktop
          ? null
          : WindowDragRegion(
              child: AppBar(
                title: Text(loc.lanChat),
                bottom: _buildTabBar(loc),
                actions: _buildAppBarActions(),
              ),
            ),
      body: Column(
        children: [
          // 桌面端:自定义标题栏(含最小化/最大化/关闭按钮)+ TabBar
          if (isDesktop) ...[
            CustomTitleBar(
              title: loc.lanChat,
              showBackButton: widget.showBackButton,
              actions: _buildAppBarActions(),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: _buildTabBar(loc),
            ),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDeviceList(),
                Consumer<ChatProvider>(
                  builder: (ctx, _, __) => _buildChatHistory(),
                ),
                const RoomListScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTabBar(AppLocalizations loc) {
    return TabBar(
      controller: _tabController,
      tabs: [
        // 图标放在文字前面,避免竖排堆叠占用过多高度
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.computer, size: 18),
              const SizedBox(width: 4),
              Text(loc.deviceList),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat, size: 18),
              const SizedBox(width: 4),
              Text(loc.chatHistory),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups, size: 18),
              const SizedBox(width: 4),
              Text(loc.roomChat),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      IconButton(
        icon: const Icon(Icons.info_outline),
        tooltip: AppLocalizations.of(context).localInfo,
        onPressed: () => _showLocalInfo(context),
      ),
      Consumer<LanDiscoveryProvider>(
        builder: (ctx, provider, _) {
          return IconButton(
            icon: Icon(provider.isRunning ? Icons.wifi : Icons.wifi_off),
            tooltip: provider.isRunning
                ? AppLocalizations.of(ctx).disableDiscovery
                : AppLocalizations.of(ctx).enableDiscovery,
            onPressed: () async {
              if (provider.isRunning) {
                provider.stop();
                return;
              }
              await provider.start();
              if (!ctx.mounted) return;
              if (provider.error != null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(
                        ctx,
                      ).discoveryStartFailedValue(provider.error!),
                    ),
                  ),
                );
              }
            },
          );
        },
      ),
    ];
  }

  Widget _buildDeviceList() {
    return Consumer<LanDiscoveryProvider>(
      builder: (ctx, provider, _) {
        if (!provider.isRunning) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 48,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).enableDiscoveryHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (provider.error != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      AppLocalizations.of(context).lastStartFailedValue(provider.error!),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        if (provider.devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).searchingDevices,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            provider.stop();
            await provider.start();
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: provider.devices.length,
            itemBuilder: (ctx, i) {
              final device = provider.devices[i];
              return DeviceTile(
                device: device,
                onConnect: () => _connectToDevice(device),
                onTap: () => _connectToDevice(device),
                onDelete: () => _confirmRemoveDevice(ctx, provider, device),
              );
            },
          ),
        );
      },
    );
  }

  /// 会话列表最后消息时间的格式化显示
  String _formatPeerTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return RelativeTime.peerTime(AppLocalizations.of(context), dt);
  }

  Widget _buildChatHistory() {
    final peers = _repository.getPeers();

    if (peers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).noChatHistory,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: peers.length,
      itemBuilder: (ctx, i) {
        final peer = peers[i];
        final peerId = peer['peer_id'] as String? ?? '';
        final isRoom = peerId.startsWith('room:');
        final peerName = peer['peer_name'] as String? ?? 'Unknown';
        final lastMessage = peer['last_message'] as String? ?? '';
        final unreadCount = peer['unread_count'] as int? ?? 0;
        final lastTimeStr = peer['last_time'] as String? ?? '';

        // 从 discovery provider 获取 IP
        final discoveryProvider = context.read<LanDiscoveryProvider>();
        final device = discoveryProvider.devices
            .where((d) => d.id == peerId)
            .toList();
        final ip = device.isNotEmpty ? device.first.ip : '';
        final port = device.isNotEmpty ? device.first.port : LanChatSettings.defaultChatPort;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (isRoom) {
                // 聊天室历史记录:房间已解散/离线后无法直接重进,切到「聊天室」页
                _tabController.animateTo(2);
                return;
              }
              _repository.markRead(peerId);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    peerId: peerId,
                    peerName: peerName,
                    peerIp: ip,
                    peerPort: port,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isRoom
                        ? Theme.of(context).colorScheme.tertiaryContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: isRoom
                        ? Icon(
                            Icons.groups,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
                          )
                        : Text(
                            peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 第一行:用户名(可省略)+ 时间(右上角)
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      peerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (isRoom) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .tertiaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context).roomChat,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (lastTimeStr.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                _formatPeerTime(lastTimeStr),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 第二行:消息预览(可省略)+ 未读徽标(右下角)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  unreadCount.toString(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onError,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 删除对话按钮
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      // 删除单个对话前二次确认,避免误删
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(AppLocalizations.of(ctx).deleteChatHistory),
                          content: Text(
                            AppLocalizations.of(ctx)
                                .confirmDeleteChatHistoryValue(peerName),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(AppLocalizations.of(ctx).cancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(AppLocalizations.of(ctx).delete),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                      _repository.deleteMessages(peerId);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
