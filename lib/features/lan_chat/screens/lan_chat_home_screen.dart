import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lan_device.dart';
import '../providers/lan_discovery_provider.dart';
import '../providers/chat_provider.dart';
import '../repositories/chat_repository.dart';
import '../services/lan_chat_settings.dart';
import '../widgets/device_tile.dart';
import '../../../widgets/window_drag_region.dart';
import 'chat_screen.dart';

/// 本地聊天首页：设备列表 + 会话列表
class LanChatHomeScreen extends StatefulWidget {
  const LanChatHomeScreen({super.key});

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
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('发现端口非默认'),
        content: Text(
          '当前发现端口为 $configured,不是默认端口 ${LanChatSettings.defaultDiscoveryPort}。\n\n'
          '发现端口需要所有设备一致,否则可能无法正常搜索到本地其他客户端。'
          '若确认其他客户端也使用相同端口,可忽略本提示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () => _resetDiscoveryPort(ctx),
            child: const Text('一键重置'),
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
      const SnackBar(content: Text('已恢复默认发现端口')),
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
        title: const Text('删除设备'),
        content: Text(
          '确定要从设备列表中移除 "${device.name}"(${device.ip}:${device.port})吗?\n\n'
          '仅移除列表中的条目,不会影响对方。若该设备仍在线,收到下一次心跳后会自动重新出现。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
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
        title: const Row(
          children: [
            Icon(Icons.info_outline, size: 20),
            SizedBox(width: 8),
            Text('本机信息'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow(Icons.lan, 'IP 地址', ip),
            const SizedBox(height: 12),
            _infoRow(Icons.settings_ethernet, '端口号', '$port'),
            const SizedBox(height: 12),
            _infoRow(Icons.person, '设备名', chatProvider.selfName),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('编辑昵称'),
            onPressed: () {
              Navigator.pop(ctx);
              _editNickname(context, chatProvider, discoveryProvider);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
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
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '请输入昵称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 20,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('昵称不能为空')));
                return;
              }
              chatProvider.setSelfName(name);
              discoveryProvider.setDeviceName(name);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('昵称已修改为 $name')));
            },
            child: const Text('保存'),
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
    return Scaffold(
      appBar: WindowDragRegion(
        child: AppBar(
          title: const Text('本地聊天'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              // 图标放在文字前面,避免竖排堆叠占用过多高度
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.computer, size: 18),
                    SizedBox(width: 4),
                    Text('设备列表'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat, size: 18),
                    SizedBox(width: 4),
                    Text('聊天记录'),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: '本机信息',
              onPressed: () => _showLocalInfo(context),
            ),
            Consumer<LanDiscoveryProvider>(
              builder: (ctx, provider, _) {
                return IconButton(
                  icon: Icon(provider.isRunning ? Icons.wifi : Icons.wifi_off),
                  tooltip: provider.isRunning ? '关闭发现' : '开启发现',
                  onPressed: () async {
                    if (provider.isRunning) {
                      provider.stop();
                      return;
                    }
                    await provider.start();
                    if (!ctx.mounted) return;
                    if (provider.error != null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('无法开启设备发现:${provider.error}')),
                      );
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDeviceList(),
          Consumer<ChatProvider>(builder: (ctx, _, __) => _buildChatHistory()),
        ],
      ),
    );
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
                  '点击右上角 WiFi 图标开启发现',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (provider.error != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      '上次启动失败:${provider.error}',
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
                  '正在搜索局域网设备...',
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
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${dt.month}/${dt.day}';
    return '${dt.year}/${dt.month}/${dt.day}';
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
              '暂无聊天记录',
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
        final port = device.isNotEmpty ? device.first.port : 19423;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    peerName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (lastTimeStr.isNotEmpty)
                  Text(
                    _formatPeerTime(lastTimeStr),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 6),
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
            subtitle: Text(
              lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                // 删除单个对话前二次确认,避免误删
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除聊天记录'),
                    content: Text('确定要删除与 "$peerName" 的聊天记录吗?删除后不可恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                _repository.deleteMessages(peerId);
                setState(() {});
              },
            ),
            onTap: () {
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
          ),
        );
      },
    );
  }
}
