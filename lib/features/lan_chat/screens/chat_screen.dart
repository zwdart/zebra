import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/custom_title_bar.dart';
import '../models/lan_models.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatProvider _chat = context.read<ChatProvider>();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final Set<String> _selected = {};
  bool _selectionMode = false;
  bool _dragOver = false;
  String _sig = '';

  Conversation? get _conv => _chat.conversation(widget.conversationId);

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChanged);
    _chat.openConversation(widget.conversationId);
    _chat.setAppVisible(true);
    final c = _conv;
    if (c != null && c.draft.isNotEmpty) _input.text = c.draft;
    _input.addListener(_onInput);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animate: false);
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.removeListener(_onInput);
    _chat.removeListener(_onChanged);
    _chat.leaveConversation();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onInput() {
    _chat.setDraft(widget.conversationId, _input.text);
    if (_input.text.trim().isNotEmpty) {
      _chat.sendTyping(true);
    } else {
      _chat.sendTyping(false);
    }
  }

  void _onChanged() {
    if (!mounted) return;
    final list = _chat.messagesOf(widget.conversationId);
    final last = list.isEmpty ? null : list.last;
    final sig =
        '${list.length}|${last?.id}|${last?.read}|${last?.recalled}'
        '|${_chat.typingNames(_conv ?? Conversation(id: '', kind: ConvKind.direct)).length}';
    if (sig == _sig) {
      setState(() {});
      return;
    }
    _sig = sig;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _chat.sendText(text);
    _scrollToBottom();
    _focus.requestFocus();
  }

  Future<void> _pickFiles() async {
    final loc = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    final added = await _chat.sendFiles(paths);
    if (added == 0 && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.translate('noSendableFiles'))));
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _selectAll() {
    final list = _chat.messagesOf(widget.conversationId);
    final all = list.map((m) => m.id).toSet();
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
        _selectionMode = false;
      } else {
        _selected
          ..clear()
          ..addAll(all);
        _selectionMode = true;
      }
    });
  }

  String _copyText(Message m) {
    final loc = AppLocalizations.of(context);
    if (m.recalled) return loc.translate('messageRecalled');
    if (m.kind == MessageKind.system) return m.text;
    if (m.kind == MessageKind.image) {
      final path = m.file?.path ?? '';
      if (path.isNotEmpty) return path;
      return m.file?.url ?? m.text;
    }
    if (m.kind == MessageKind.file) {
      final file = m.file;
      if (file == null) return m.text;
      final path = file.path.isNotEmpty ? file.path : file.url;
      return path.isNotEmpty ? path : file.name;
    }
    return m.text;
  }

  Future<void> _copyMessages(List<Message> list) async {
    final loc = AppLocalizations.of(context);
    if (list.isEmpty) return;
    final text = list.map(_copyText).where((s) => s.isNotEmpty).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.copied)));
  }

  void _copySelected() {
    final list = _chat
        .messagesOf(widget.conversationId)
        .where((m) => _selected.contains(m.id))
        .toList();
    _copyMessages(list);
  }

  Future<void> _shareSelected() async {
    final list = _chat
        .messagesOf(widget.conversationId)
        .where((m) => _selected.contains(m.id))
        .toList();
    final files = <XFile>[];
    for (final m in list) {
      final path = m.file?.path ?? '';
      if (path.isNotEmpty && await File(path).exists()) files.add(XFile(path));
    }
    if (files.isNotEmpty) {
      await Share.shareXFiles(files);
      return;
    }
    final text = list.map(_copyText).where((s) => s.isNotEmpty).join('\n\n');
    if (text.isNotEmpty) await Share.share(text);
  }

  Future<void> _deleteSelected() async {
    final loc = AppLocalizations.of(context);
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.deleteMessages),
        content: Text(loc.confirmDeleteMessagesValue(_selected.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _chat.deleteMessages(widget.conversationId, _selected.toList());
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  Future<void> _deleteMessage(Message m) async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.deleteMessages),
        content: Text(loc.confirmDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.delete),
          ),
        ],
      ),
    );
    if (ok == true) _chat.deleteMessage(widget.conversationId, m.id);
  }

  Future<void> _onMessageMenu(Message m, Offset position) async {
    final loc = AppLocalizations.of(context);
    final c = _conv;
    if (c == null) return;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (m.kind != MessageKind.system)
          PopupMenuItem(value: 'copy', child: Text(loc.translate('copy'))),
        if (m.kind != MessageKind.system)
          PopupMenuItem(value: 'select', child: Text(loc.translate('select'))),
        if (m.file != null && !m.recalled) ...[
          PopupMenuItem(
            value: 'download',
            child: Text(loc.translate('download')),
          ),
          if (m.file!.path.isNotEmpty)
            PopupMenuItem(value: 'open', child: Text(loc.translate('open'))),
          if (m.file!.path.isNotEmpty)
            PopupMenuItem(value: 'share', child: Text(loc.translate('share'))),
        ],
        if (m.mine && !m.recalled)
          PopupMenuItem(value: 'recall', child: Text(loc.translate('recall'))),
        PopupMenuItem(value: 'delete', child: Text(loc.delete)),
      ],
    );
    if (value == null || !mounted) return;
    switch (value) {
      case 'copy':
        await _copyMessages([m]);
        break;
      case 'select':
        _enterSelection(m.id);
        break;
      case 'download':
        final path = await _chat.downloadMessage(c.id, m.id);
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.translate('savedTo')}$path')),
          );
        }
        break;
      case 'open':
        await _openFile(m);
        break;
      case 'share':
        await _shareMessage(m);
        break;
      case 'recall':
        _chat.recallMessage(c.id, m.id);
        break;
      case 'delete':
        await _deleteMessage(m);
        break;
    }
  }

  Future<void> _openFile(Message m) async {
    final path = m.file?.path ?? '';
    if (path.isEmpty) return;
    try {
      await launchUrl(Uri.file(path));
    } catch (_) {
      await Share.shareXFiles([XFile(path)]);
    }
  }

  Future<void> _shareMessage(Message m) async {
    final path = m.file?.path ?? '';
    if (path.isNotEmpty && await File(path).exists()) {
      await Share.shareXFiles([XFile(path)]);
      return;
    }
    final text = _copyText(m);
    if (text.isNotEmpty) await Share.share(text);
  }

  Future<void> _copyAll() async {
    await _copyMessages(_chat.messagesOf(widget.conversationId));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final c = _conv;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(loc.translate('conversationMissing'))),
      );
    }
    final isDesktop = CustomTitleBar.isDesktop;
    final title = _chat.conversationTitle(c);
    final subtitle = _subtitle(loc, c);
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: _title(context, title, subtitle),
              actions: _selectionMode
                  ? _selectionActions(loc)
                  : _actions(loc, c),
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: title,
              showBackButton: true,
              actions: _selectionMode
                  ? _selectionActions(loc)
                  : _actions(loc, c),
            ),
          if (isDesktop) _desktopSubtitle(context, subtitle),
          if (_selectionMode) _selectionBar(loc),
          Expanded(child: _messageArea(c)),
          _typingBar(loc, c),
          _inputBar(loc),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (subtitle != null)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _desktopSubtitle(BuildContext context, String? subtitle) {
    if (subtitle == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String? _subtitle(AppLocalizations loc, Conversation c) {
    if (c.kind == ConvKind.group) {
      return '${loc.translate('members')} · ${c.members.length}';
    }
    final peer = _chat.peer(c.peerId);
    if (peer.connected) {
      return '${peer.addr} · ${loc.connected}';
    }
    return '${peer.addr} · ${loc.disconnected}';
  }

  List<Widget> _actions(AppLocalizations loc, Conversation c) {
    return [
      IconButton(
        icon: const Icon(Icons.copy_all),
        tooltip: loc.translate('copyAll'),
        onPressed: _copyAll,
      ),
      IconButton(
        icon: const Icon(Icons.checklist),
        tooltip: loc.multiSelect,
        onPressed: () {
          setState(() {
            _selectionMode = true;
            _selected.clear();
          });
        },
      ),
      IconButton(
        icon: const Icon(Icons.info_outline),
        tooltip: loc.chatDetails,
        onPressed: () => _showInfo(c),
      ),
    ];
  }

  List<Widget> _selectionActions(AppLocalizations loc) {
    return [
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: loc.cancel,
        onPressed: () => setState(() {
          _selectionMode = false;
          _selected.clear();
        }),
      ),
      IconButton(
        icon: const Icon(Icons.select_all),
        tooltip: loc.translate('selectAll'),
        onPressed: _selectAll,
      ),
      IconButton(
        icon: const Icon(Icons.copy),
        tooltip: loc.translate('copySelected'),
        onPressed: _selected.isEmpty ? null : _copySelected,
      ),
      IconButton(
        icon: const Icon(Icons.ios_share),
        tooltip: loc.translate('share'),
        onPressed: _selected.isEmpty ? null : _shareSelected,
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: loc.deleteMessages,
        onPressed: _selected.isEmpty ? null : _deleteSelected,
      ),
    ];
  }

  Widget _selectionBar(AppLocalizations loc) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(loc.selectedCountValue(_selected.length)),
            const Spacer(),
            TextButton(
              onPressed: _selectAll,
              child: Text(loc.translate('selectAll')),
            ),
            TextButton(
              onPressed: _selected.isEmpty ? null : _copySelected,
              child: Text(loc.translate('copySelected')),
            ),
            TextButton(
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              child: Text(loc.delete),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageArea(Conversation c) {
    final list = _chat.messagesOf(widget.conversationId);
    if (list.isEmpty) {
      return DropTarget(
        onDragEntered: (_) => setState(() => _dragOver = true),
        onDragExited: (_) => setState(() => _dragOver = false),
        onDragDone: (details) {
          setState(() => _dragOver = false);
          final paths = details.files.map((f) => f.path).toList();
          if (paths.isNotEmpty) _chat.sendFiles(paths);
        },
        child: Center(
          child: _dragOver
              ? const Icon(Icons.download, size: 56)
              : _EmptyChat(text: AppLocalizations.of(context).startChat),
        ),
      );
    }
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragDone: (details) {
        setState(() => _dragOver = false);
        final paths = details.files.map((f) => f.path).toList();
        if (paths.isNotEmpty) _chat.sendFiles(paths);
      },
      child: Stack(
        children: [
          ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final m = list[i];
              final prev = i == 0 ? null : list[i - 1];
              final showName =
                  c.kind == ConvKind.group &&
                  !m.mine &&
                  m.kind != MessageKind.system &&
                  (prev == null ||
                      prev.senderId != m.senderId ||
                      prev.kind == MessageKind.system);
              return MessageBubble(
                message: m,
                conversation: c,
                showSender: showName,
                senderName: _chat.peerName(m.senderId),
                selectionMode: _selectionMode,
                selected: _selected.contains(m.id),
                download: _chat.downloads[m.id],
                sendProgress: _chat.sends[m.id],
                onTap: _selectionMode ? () => _toggleSelect(m.id) : null,
                onMenu: (pos) => _onMessageMenu(m, pos),
                onDownload: () => _chat.downloadMessage(c.id, m.id),
                onOpen: () => _openFile(m),
                onShare: () => _shareMessage(m),
                onToggleSelect: () => _toggleSelect(m.id),
              );
            },
          ),
          if (_dragOver)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
                  child: const Center(child: Icon(Icons.download, size: 64)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _typingBar(AppLocalizations loc, Conversation c) {
    final names = _chat.typingNames(c);
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${names.join(', ')} ${loc.translate('isTyping')}',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _inputBar(AppLocalizations loc) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: loc.sendFile,
              onPressed: _pickFiles,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: loc.messageHint,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              icon: const Icon(Icons.send),
              tooltip: loc.send,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInfo(Conversation c) async {
    final loc = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _chat.conversationTitle(c),
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  if (c.kind == ConvKind.group && c.owner == _chat.profile.id)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _renameGroup(c);
                      },
                      child: Text(loc.translate('rename')),
                    ),
                ],
              ),
              if (c.kind == ConvKind.direct) ...[
                const SizedBox(height: 8),
                _infoLine(ctx, loc.ipAddress, _chat.peer(c.peerId).ip),
                _infoLine(ctx, loc.portNumber, '${_chat.peer(c.peerId).port}'),
                _infoLine(
                  ctx,
                  loc.translate('transferPort'),
                  '${_chat.peer(c.peerId).transferPort}',
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  '${loc.translate('members')} (${c.members.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                for (final p in _chat.groupMembers(c))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        p.displayName.isEmpty
                            ? '?'
                            : p.displayName.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(
                      '${p.displayName}${p.id == _chat.profile.id ? ' (${loc.localDevice})' : ''}',
                    ),
                    subtitle: p.id == _chat.profile.id
                        ? null
                        : Text(p.addr, style: const TextStyle(fontSize: 12)),
                    trailing:
                        c.owner == _chat.profile.id && p.id != _chat.profile.id
                        ? IconButton(
                            icon: const Icon(Icons.person_remove_outlined),
                            tooltip: loc.translate('removeMember'),
                            onPressed: () {
                              _chat.removeGroupMember(c.id, p.id);
                              Navigator.pop(ctx);
                            },
                          )
                        : null,
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _addMembers(c);
                      },
                      icon: const Icon(Icons.group_add),
                      label: Text(loc.translate('addMembers')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (c.owner == _chat.profile.id) {
                          _chat.disbandGroup(c);
                        } else {
                          _chat.leaveGroup(c);
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: Text(
                        c.owner == _chat.profile.id
                            ? loc.translate('disbandGroup')
                            : loc.translate('leaveGroup'),
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  c.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(
                  c.pinned ? loc.translate('unpin') : loc.translate('pin'),
                ),
                onTap: () {
                  _chat.togglePinned(c.id);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  c.muted
                      ? Icons.notifications_off
                      : Icons.notifications_outlined,
                ),
                title: Text(
                  c.muted ? loc.translate('unmute') : loc.translate('mute'),
                ),
                onTap: () {
                  _chat.toggleMuted(c.id);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(loc.translate('clearHistory')),
                onTap: () {
                  _chat.clearHistory(c.id);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Future<void> _renameGroup(Conversation c) async {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController(text: c.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.translate('rename')),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(loc.save),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) _chat.renameGroup(c.id, name);
  }

  Future<void> _addMembers(Conversation c) async {
    final loc = AppLocalizations.of(context);
    final existing = c.members.toSet();
    final candidates = _chat
        .sortedPeers()
        .where((p) => !existing.contains(p.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.translate('noDevices'))));
      return;
    }
    final selected = <String>{};
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.translate('selectMembers')),
          content: SizedBox(
            width: 380,
            height: 360,
            child: ListView.builder(
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final p = candidates[i];
                return CheckboxListTile(
                  value: selected.contains(p.id),
                  title: Text(p.displayName),
                  subtitle: Text(p.addr, style: const TextStyle(fontSize: 12)),
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
              child: Text(loc.translate('add')),
            ),
          ],
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      _chat.addGroupMembers(c.id, picked);
    }
  }
}

class _EmptyChat extends StatelessWidget {
  final String text;

  const _EmptyChat({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
