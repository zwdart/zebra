import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/relative_time.dart';
import '../../../widgets/custom_title_bar.dart';
import '../../../widgets/window_drag_region.dart';
import '../models/lan_models.dart';
import '../models/peer.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';

class LanChatHomeScreen extends StatefulWidget {
  final bool showBackButton;

  const LanChatHomeScreen({super.key, this.showBackButton = false});

  @override
  State<LanChatHomeScreen> createState() => _LanChatHomeScreenState();
}

class _LanChatHomeScreenState extends State<LanChatHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  ChatProvider get _chat => context.read<ChatProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chat.setAppVisible(true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _chat.setAppVisible(state == AppLifecycleState.resumed);
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
                bottom: _tabBar(loc),
                actions: _actions(loc),
              ),
            ),
      body: Column(
        children: [
          if (isDesktop) ...[
            CustomTitleBar(
              title: loc.lanChat,
              showBackButton: widget.showBackButton,
              actions: _actions(loc),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: _tabBar(loc),
            ),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DeviceList(onOpen: _openPeer, onManualConnect: _manualConnect),
                _ConversationList(
                  groups: false,
                  onOpen: _openConversation,
                  onCreateGroup: _createGroup,
                ),
                _ConversationList(
                  groups: true,
                  onOpen: _openConversation,
                  onCreateGroup: _createGroup,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _tabBar(AppLocalizations loc) {
    return TabBar(
      controller: _tabs,
      tabs: [
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.devices, size: 18),
              const SizedBox(width: 6),
              Text(loc.deviceList),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 18),
              const SizedBox(width: 6),
              Text(loc.chatHistory),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_outlined, size: 18),
              const SizedBox(width: 6),
              Text(loc.translate('groups')),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(AppLocalizations loc) {
    return [
      Consumer<ChatProvider>(
        builder: (ctx, chat, _) => IconButton(
          icon: Icon(chat.node != null ? Icons.wifi : Icons.wifi_off),
          tooltip: chat.settings.discovery
              ? loc.disableDiscovery
              : loc.enableDiscovery,
          onPressed: () async {
            await chat.setDiscovery(!chat.settings.discovery);
            if (!ctx.mounted) return;
            if (!chat.settings.discovery) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(SnackBar(content: Text(loc.enableDiscoveryHint)));
            }
          },
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add_link),
        tooltip: loc.translate('manualConnect'),
        onPressed: () => _manualConnect(context),
      ),
      IconButton(
        icon: const Icon(Icons.folder_shared_outlined),
        tooltip: loc.translate('shareServer'),
        onPressed: () => _showShareDialog(context),
      ),
      IconButton(
        icon: const Icon(Icons.info_outline),
        tooltip: loc.localInfo,
        onPressed: () => _showLocalInfo(context),
      ),
      IconButton(
        icon: const Icon(Icons.tune),
        tooltip: loc.translate('chatSettings'),
        onPressed: () => _showSettings(context),
      ),
    ];
  }

  void _openPeer(Peer peer) {
    final c = _chat.ensureDirect(peer);
    _openConversation(c);
  }

  void _openConversation(Conversation c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(conversationId: c.id)),
    );
  }

  Future<void> _manualConnect(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController();
    final addr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.translate('manualConnect')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '192.168.1.10:42224',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(loc.translate('connect')),
          ),
        ],
      ),
    );
    if (addr == null || addr.isEmpty) return;
    try {
      final peer = await _chat.manualConnect(addr);
      if (!context.mounted) return;
      _chat.ensureDirect(peer);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.connected}: ${peer.displayName}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${loc.translate('connectFailed')}: ${e.toString().replaceFirst('Bad state: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _showLocalInfo(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final chat = _chat;
    final ips = chat.localIps;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.localInfo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _info(ctx, loc.localInfoIp, ips.isEmpty ? '-' : ips.join('\n')),
            _info(ctx, loc.localInfoPort, '${chat.port}'),
            _info(ctx, loc.translate('transferPort'), '${chat.transferPort}'),
            _info(ctx, loc.translate('sharePort'), '${chat.sharePort}'),
            _info(ctx, loc.localInfoDeviceName, chat.profile.name),
            _info(ctx, loc.translate('deviceId'), chat.profile.id),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.close),
          ),
        ],
      ),
    );
  }

  Widget _info(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showShareDialog(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final chat = _chat;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final urls = chat.shareUrls();
          return AlertDialog(
            title: Text(loc.translate('shareServer')),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.shareRunning
                        ? loc.translate('shareRunning')
                        : loc.translate('shareStopped'),
                    style: TextStyle(
                      color: chat.shareRunning
                          ? Colors.green
                          : Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (urls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final url in urls)
                      SelectableText(
                        url,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  _dirRow(
                    ctx,
                    loc.translate('shareDir'),
                    chat.settings.shareDir,
                    (path) async {
                      await chat.setSettings((s) => s.shareDir = path);
                      if (chat.shareRunning) await chat.startShare();
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  _dirRow(
                    ctx,
                    loc.translate('uploadDir'),
                    chat.settings.uploadDir,
                    (path) async {
                      await chat.setSettings((s) => s.uploadDir = path);
                      if (chat.shareRunning) await chat.startShare();
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(loc.close),
              ),
              if (chat.shareRunning)
                FilledButton.tonal(
                  onPressed: () async {
                    await chat.stopShare();
                    setDialogState(() {});
                  },
                  child: Text(loc.translate('stopShare')),
                )
              else
                FilledButton(
                  onPressed: () async {
                    await chat.startShare();
                    setDialogState(() {});
                  },
                  child: Text(loc.translate('startShare')),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dirRow(
    BuildContext context,
    String label,
    String path,
    Future<void> Function(String path) onPicked,
  ) {
    final loc = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                path.isEmpty ? loc.translate('notSet') : path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            final dir = await FilePicker.platform.getDirectoryPath();
            if (dir != null && dir.isNotEmpty) await onPicked(dir);
          },
          child: Text(loc.translate('choose')),
        ),
        if (path.isNotEmpty)
          IconButton(
            tooltip: loc.translate('clear'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => onPicked(''),
          ),
      ],
    );
  }

  Future<void> _showSettings(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final chat = _chat;
    final name = TextEditingController(text: chat.profile.name);
    final signature = TextEditingController(text: chat.profile.signature);
    var status = chat.profile.status;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.translate('chatSettings')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: loc.localInfoDeviceName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: signature,
                  decoration: InputDecoration(
                    labelText: loc.translate('signature'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Presence>(
                  initialValue: status,
                  decoration: InputDecoration(
                    labelText: loc.translate('status'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in presenceOptions)
                      DropdownMenuItem(
                        value: p,
                        child: Text(_presenceLabel(loc, p)),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => status = v ?? status),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.translate('autoDownloadImages')),
                  value: chat.settings.autoDownloadImages,
                  onChanged: (v) async {
                    await chat.setSettings((s) => s.autoDownloadImages = v);
                    setDialogState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.enableDiscovery),
                  value: chat.settings.discovery,
                  onChanged: (v) async {
                    await chat.setDiscovery(v);
                    setDialogState(() {});
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.cancel),
            ),
            FilledButton(
              onPressed: () async {
                await chat.updateProfile(
                  name: name.text,
                  signature: signature.text,
                );
                await chat.setStatus(status);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(loc.save),
            ),
          ],
        ),
      ),
    );
  }

  String _presenceLabel(AppLocalizations loc, Presence p) {
    const keys = {
      Presence.online: 'online',
      Presence.away: 'away',
      Presence.busy: 'busy',
      Presence.dnd: 'dnd',
      Presence.invisible: 'invisible',
      Presence.offline: 'offline',
    };
    return loc.translate(keys[p] ?? 'online');
  }

  Future<void> _createGroup() async {
    final loc = AppLocalizations.of(context);
    final name = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.translate('createGroup')),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: InputDecoration(
            hintText: loc.translate('groupNameHint'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, name.text.trim()),
            child: Text(loc.translate('next')),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final picked = await _pickMembers(loc);
    if (picked == null || !mounted) return;
    final c = _chat.createGroup(title, picked);
    if (mounted) _openConversation(c);
  }

  Future<List<String>?> _pickMembers(AppLocalizations loc) async {
    final peers = _chat.sortedPeers();
    final selected = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.translate('selectMembers')),
          content: SizedBox(
            width: 380,
            height: 360,
            child: peers.isEmpty
                ? Center(child: Text(loc.translate('noDevices')))
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (_, i) {
                      final p = peers[i];
                      return CheckboxListTile(
                        value: selected.contains(p.id),
                        title: Text(p.displayName),
                        subtitle: Text(
                          p.addr,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selected.add(p.id);
                          } else {
                            selected.remove(p.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected.toList()),
              child: Text(loc.translate('create')),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  final void Function(Peer peer) onOpen;
  final Future<void> Function(BuildContext context) onManualConnect;

  const _DeviceList({required this.onOpen, required this.onManualConnect});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Consumer<ChatProvider>(
      builder: (ctx, chat, _) {
        if (!chat.settings.discovery) {
          return _Empty(
            icon: Icons.wifi_off,
            text: loc.enableDiscoveryHint,
            action: FilledButton.icon(
              onPressed: () => chat.setDiscovery(true),
              icon: const Icon(Icons.wifi),
              label: Text(loc.enableDiscovery),
            ),
          );
        }
        final peers = chat.sortedPeers();
        if (peers.isEmpty) {
          return _Empty(
            icon: Icons.radar,
            text: loc.searchingDevices,
            action: OutlinedButton.icon(
              onPressed: () => onManualConnect(context),
              icon: const Icon(Icons.add_link),
              label: Text(loc.translate('manualConnect')),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: peers.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final p = peers[i];
            return ListTile(
              leading: _PresenceAvatar(peer: p),
              title: Text(p.displayName),
              subtitle: Text(
                '${p.addr}${p.platform.isEmpty ? '' : ' · ${p.platform}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'chat') onOpen(p);
                  if (value == 'alias') {
                    final c = TextEditingController(text: p.alias);
                    final alias = await showDialog<String>(
                      context: ctx,
                      builder: (dctx) => AlertDialog(
                        title: Text(loc.translate('alias')),
                        content: TextField(
                          controller: c,
                          decoration: InputDecoration(
                            hintText: p.name,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx),
                            child: Text(loc.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dctx, c.text.trim()),
                            child: Text(loc.save),
                          ),
                        ],
                      ),
                    );
                    if (alias != null) chat.setAlias(p.id, alias);
                  }
                  if (value == 'remove') {
                    if (!ctx.mounted) return;
                    final ok = await showDialog<bool>(
                      context: ctx,
                      builder: (dctx) => AlertDialog(
                        title: Text(loc.deleteDevice),
                        content: Text(
                          loc.confirmDeleteDeviceValue(p.displayName, p.addr),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx, false),
                            child: Text(loc.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dctx, true),
                            child: Text(loc.delete),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) chat.removePeer(p.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'chat', child: Text(loc.startChat)),
                  PopupMenuItem(
                    value: 'alias',
                    child: Text(loc.translate('alias')),
                  ),
                  PopupMenuItem(value: 'remove', child: Text(loc.deleteDevice)),
                ],
              ),
              onTap: () => onOpen(p),
            );
          },
        );
      },
    );
  }
}

class _ConversationList extends StatelessWidget {
  final bool groups;
  final void Function(Conversation c) onOpen;
  final VoidCallback onCreateGroup;

  const _ConversationList({
    required this.groups,
    required this.onOpen,
    required this.onCreateGroup,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Consumer<ChatProvider>(
      builder: (ctx, chat, _) {
        final list = chat.orderedConversations().where((c) {
          return groups ? c.kind == ConvKind.group : c.kind == ConvKind.direct;
        }).toList();
        if (list.isEmpty) {
          return _Empty(
            icon: groups ? Icons.groups_outlined : Icons.chat_bubble_outline,
            text: loc.noChatHistory,
            action: groups
                ? FilledButton.icon(
                    onPressed: onCreateGroup,
                    icon: const Icon(Icons.group_add),
                    label: Text(loc.translate('createGroup')),
                  )
                : null,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final c = list[i];
            final last = c.last;
            final preview = last == null ? '' : _preview(loc, last);
            return ListTile(
              leading: _ConversationAvatar(c: c),
              title: Row(
                children: [
                  if (c.pinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin, size: 14),
                    ),
                  Expanded(
                    child: Text(
                      chat.conversationTitle(c),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (c.muted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.notifications_off, size: 14),
                    ),
                  if (last != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        RelativeTime.peerTime(loc, last.sentAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                c.draft.isNotEmpty
                    ? '${loc.translate('draft')}: ${c.draft}'
                    : preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: c.unread > 0
                  ? CircleAvatar(
                      radius: 11,
                      child: Text(
                        '${c.unread}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    )
                  : null,
              onTap: () => onOpen(c),
              onLongPress: () => _menu(context, chat, c),
            );
          },
        );
      },
    );
  }

  String _preview(AppLocalizations loc, Message m) {
    if (m.recalled) return loc.translate('messageRecalled');
    if (m.kind == MessageKind.image) {
      return m.text.isEmpty
          ? loc.translate('imageLabel')
          : '${loc.translate('imageLabel')} ${m.text}';
    }
    if (m.kind == MessageKind.file) {
      return '${loc.translate('fileLabel')} ${m.file?.name ?? ''}';
    }
    if (m.kind == MessageKind.system) return m.text;
    return m.text.replaceAll('\n', ' ');
  }

  Future<void> _menu(
    BuildContext context,
    ChatProvider chat,
    Conversation c,
  ) async {
    final loc = AppLocalizations.of(context);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(c.pinned ? loc.translate('unpin') : loc.translate('pin')),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Text(
            c.muted ? loc.translate('unmute') : loc.translate('mute'),
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: Text(loc.translate('clearHistory')),
        ),
        if (c.kind == ConvKind.group)
          PopupMenuItem(
            value: c.owner == chat.profile.id ? 'disband' : 'leave',
            child: Text(
              c.owner == chat.profile.id
                  ? loc.translate('disbandGroup')
                  : loc.translate('leaveGroup'),
            ),
          )
        else
          PopupMenuItem(value: 'delete', child: Text(loc.deleteChatHistory)),
      ],
    );
    if (value == null || !context.mounted) return;
    switch (value) {
      case 'pin':
        chat.togglePinned(c.id);
        break;
      case 'mute':
        chat.toggleMuted(c.id);
        break;
      case 'clear':
        chat.clearHistory(c.id);
        break;
      case 'delete':
        chat.deleteConversation(c.id);
        break;
      case 'leave':
        chat.leaveGroup(c);
        break;
      case 'disband':
        chat.disbandGroup(c);
        break;
    }
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Empty({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _PresenceAvatar extends StatelessWidget {
  final Peer peer;

  const _PresenceAvatar({required this.peer});

  @override
  Widget build(BuildContext context) {
    final color = peer.connected
        ? (peer.status == Presence.busy || peer.status == Presence.dnd
              ? Colors.orange
              : Colors.green)
        : Colors.grey;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          child: Text(
            peer.displayName.isEmpty
                ? '?'
                : peer.displayName.characters.first.toUpperCase(),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  final Conversation c;

  const _ConversationAvatar({required this.c});

  @override
  Widget build(BuildContext context) {
    if (c.kind == ConvKind.group) {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        child: const Icon(Icons.groups),
      );
    }
    final chat = context.read<ChatProvider>();
    final peer = chat.peer(c.peerId);
    return _PresenceAvatar(peer: peer);
  }
}
