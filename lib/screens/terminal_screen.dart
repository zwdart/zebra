import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../providers/ssh_provider.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'monitor_screen.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final ScrollController _tabScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFirstTab();
    });
  }

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  Future<void> _initFirstTab() async {
    final sshProvider = context.read<SshProvider>();
    if (!sshProvider.isConnected) return;

    if (sshProvider.sessions.isEmpty) {
      await sshProvider.addTerminalSession(cols: 120, rows: 30);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final sshProvider = context.watch<SshProvider>();
    final conn = sshProvider.currentConnection;
    final sessions = sshProvider.sessions;

    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text('${conn?.name ?? "SSH"} - ${loc.terminal}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: loc.newTab,
            onPressed: _addTab,
          ),
          IconButton(
            icon: const Icon(Icons.monitor_heart),
            tooltip: loc.serverMonitor,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MonitorScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_copy),
            tooltip: loc.sftp,
            onPressed: () => Navigator.pushNamed(context, '/sftp'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect',
            onPressed: _reconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: '${conn?.name ?? "SSH"} - ${loc.terminal}',
              showBackButton: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: loc.newTab,
                  onPressed: _addTab,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: const Icon(Icons.monitor_heart, size: 18),
                  tooltip: loc.serverMonitor,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MonitorScreen()),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: const Icon(Icons.file_copy, size: 18),
                  tooltip: loc.sftp,
                  onPressed: () => Navigator.pushNamed(context, '/sftp'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Reconnect',
                  onPressed: _reconnect,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          _buildBody(sessions, sshProvider),
        ],
      ),
    );
  }

  Widget _buildBody(List sessions, SshProvider sshProvider) {
    final loc = AppLocalizations.of(context);

    if (!sshProvider.isConnected) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(loc.connectionError),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _reconnect,
                child: Text(loc.connect),
              ),
            ],
          ),
        ),
      );
    }

    if (sessions.isEmpty) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    return Expanded(
      child: Column(
        children: [
          _buildTabBar(sessions, sshProvider),
          Expanded(child: _buildActiveTerminal(sshProvider)),
        ],
      ),
    );
  }

  Widget _buildTabBar(List sessions, SshProvider sshProvider) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _tabScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isActive = index == sshProvider.activeSessionIndex;

                return _buildTabItem(session, index, isActive, sshProvider);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    dynamic session,
    int index,
    bool isActive,
    SshProvider sshProvider,
  ) {
    final theme = Theme.of(context);
    final sessions = sshProvider.sessions;

    final tabContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 0.5),
          bottom: BorderSide(
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 16,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            session.label,
            style: TextStyle(
              fontSize: 13,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 6),
          if (sessions.length > 1)
            GestureDetector(
              onTap: () => sshProvider.closeTerminalSession(index),
              child: Icon(
                Icons.close,
                size: 16,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    // Desktop: support right-click menu and middle-click close
    if (CustomTitleBar.isDesktop) {
      return GestureDetector(
        onTap: () => sshProvider.switchSession(index),
        onSecondaryTapUp: (details) => _showTabContextMenu(
          details.globalPosition,
          index,
          sshProvider,
        ),
        onTertiaryTapUp: (details) {
          sshProvider.closeTerminalSession(index);
        },
        child: tabContent,
      );
    }

    // Mobile: support long-press menu
    return GestureDetector(
      onTap: () => sshProvider.switchSession(index),
      onLongPress: () => _showTabContextMenu(
        null,
        index,
        sshProvider,
      ),
      child: tabContent,
    );
  }

  void _showTabContextMenu(Offset? position, int index, SshProvider sshProvider) {
    final loc = AppLocalizations.of(context);
    final sessions = sshProvider.sessions;

    if (CustomTitleBar.isDesktop && position != null) {
      // Desktop: show popup menu at position
      showMenu(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx + 1,
          position.dy + 1,
        ),
        items: <PopupMenuEntry<String>>[
          PopupMenuItem(
            value: 'new',
            child: Row(
              children: [
                const Icon(Icons.add, size: 18),
                const SizedBox(width: 8),
                Text(loc.newTab),
              ],
            ),
          ),
          if (sessions.length > 1) ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'close',
              child: Row(
                children: [
                  const Icon(Icons.close, size: 18),
                  const SizedBox(width: 8),
                  Text(loc.closeTab),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'close_others',
              child: Row(
                children: [
                  const Icon(Icons.close_fullscreen, size: 18),
                  const SizedBox(width: 8),
                  Text(loc.closeOtherTabs),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'close_all',
              child: Row(
                children: [
                  const Icon(Icons.close_fullscreen, size: 18),
                  const SizedBox(width: 8),
                  Text(loc.closeAllTabs),
                ],
              ),
            ),
          ],
        ],
      ).then((value) {
        if (value == null) return;
        _handleTabMenuAction(value, index, sshProvider);
      });
    } else {
      // Mobile: show bottom sheet
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(loc.newTab),
                onTap: () {
                  Navigator.pop(ctx);
                  _addTab();
                },
              ),
              if (sessions.length > 1) ...[
                ListTile(
                  leading: const Icon(Icons.close),
                  title: Text(loc.closeTab),
                  onTap: () {
                    Navigator.pop(ctx);
                    sshProvider.closeTerminalSession(index);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_fullscreen),
                  title: Text(loc.closeOtherTabs),
                  onTap: () {
                    Navigator.pop(ctx);
                    _closeOtherTabs(index, sshProvider);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_fullscreen),
                  title: Text(loc.closeAllTabs),
                  onTap: () {
                    Navigator.pop(ctx);
                    _closeAllTabs(sshProvider);
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }
  }

  void _handleTabMenuAction(String action, int index, SshProvider sshProvider) {
    switch (action) {
      case 'new':
        _addTab();
        break;
      case 'close':
        sshProvider.closeTerminalSession(index);
        break;
      case 'close_others':
        _closeOtherTabs(index, sshProvider);
        break;
      case 'close_all':
        _closeAllTabs(sshProvider);
        break;
    }
  }

  void _closeOtherTabs(int keepIndex, SshProvider sshProvider) {
    final sessions = sshProvider.sessions;
    // Close from highest index to lowest to avoid shifting issues
    for (int i = sessions.length - 1; i >= 0; i--) {
      if (i != keepIndex) {
        sshProvider.closeTerminalSession(i);
      }
    }
  }

  void _closeAllTabs(SshProvider sshProvider) {
    for (int i = sshProvider.sessions.length - 1; i >= 0; i--) {
      sshProvider.closeTerminalSession(i);
    }
  }

  Widget _buildActiveTerminal(SshProvider sshProvider) {
    final session = sshProvider.activeSession;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (session.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (session.terminal == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context).terminalNotAvailable),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _reconnect,
              child: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      );
    }

    return _TerminalWidget(
      terminal: session.terminal!,
      key: ValueKey(session.id),
    );
  }

  void _addTab() async {
    final sshProvider = context.read<SshProvider>();
    if (!sshProvider.isConnected) return;

    final success = await sshProvider.addTerminalSession(cols: 120, rows: 30);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum ${SshProvider.maxSessions} tabs reached'),
        ),
      );
    }
  }

  void _reconnect() async {
    final sshProvider = context.read<SshProvider>();
    final conn = sshProvider.currentConnection;
    if (conn == null) return;

    sshProvider.disconnect();
    await sshProvider.connect(conn);

    if (mounted) {
      if (sshProvider.isConnected) {
        _initFirstTab();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).connectionError}: ${sshProvider.error}'),
          ),
        );
      }
    }
  }
}

class _TerminalWidget extends StatefulWidget {
  final Terminal terminal;

  const _TerminalWidget({required this.terminal, super.key});

  @override
  State<_TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<_TerminalWidget> {
  final _terminalFocusNode = FocusNode();
  final _terminalKey = GlobalKey();
  final _controller = TerminalController();
  OverlayEntry? _selectionOverlay;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _terminalFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _removeSelectionOverlay();
    _controller.removeListener(_onSelectionChanged);
    _terminalFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final hasSelection = _controller.selection != null;
    if (hasSelection && !CustomTitleBar.isDesktop) {
      // 移动端：选中文本后显示菜单
      _showSelectionOverlay();
    } else {
      _removeSelectionOverlay();
    }
  }

  void _showSelectionOverlay() {
    _removeSelectionOverlay();

    final renderObject = _terminalKey.currentContext?.findRenderObject();
    if (renderObject == null) return;

    final RenderBox renderBox = renderObject as RenderBox;
    final size = renderBox.size;

    _selectionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        left: size.width / 2 - 120,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildOverlayButton(
                  icon: Icons.copy,
                  tooltip: AppLocalizations.of(context).copy,
                  onPressed: () {
                    _copySelection();
                    _removeSelectionOverlay();
                  },
                ),
                Container(width: 1, height: 24, color: Theme.of(context).dividerColor),
                _buildOverlayButton(
                  icon: Icons.paste,
                  tooltip: AppLocalizations.of(context).paste,
                  onPressed: () {
                    _pasteFromClipboard();
                    _removeSelectionOverlay();
                  },
                ),
                Container(width: 1, height: 24, color: Theme.of(context).dividerColor),
                _buildOverlayButton(
                  icon: Icons.select_all,
                  tooltip: AppLocalizations.of(context).selectAll,
                  onPressed: () {
                    _selectAll();
                    _removeSelectionOverlay();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_selectionOverlay!);
  }

  void _removeSelectionOverlay() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = CustomTitleBar.isDesktop;

    return TerminalView(
      widget.terminal,
      key: _terminalKey,
      controller: _controller,
      focusNode: _terminalFocusNode,
      autofocus: true,
      hardwareKeyboardOnly: isDesktop,
      deleteDetection: !isDesktop,
      keyboardType: TextInputType.text,
      onSecondaryTapUp: isDesktop ? _onRightClick : null,
      textStyle: TerminalStyle(
        fontSize: 14,
        fontFamily: isDesktop
            ? (Platform.isWindows ? 'Consolas' : 'monospace')
            : 'monospace',
      ),
    );
  }

  void _onRightClick(TapUpDetails details, CellOffset offset) {
    final hasSelection = _controller.selection != null;
    final renderObject = _terminalKey.currentContext?.findRenderObject();
    if (renderObject == null) return;

    final RenderBox renderBox = renderObject as RenderBox;
    final globalPosition = renderBox.localToGlobal(details.localPosition);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          enabled: hasSelection,
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18),
              const SizedBox(width: 8),
              Text('${AppLocalizations.of(context).copy} (Ctrl+Shift+C)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          child: Row(
            children: [
              const Icon(Icons.paste, size: 18),
              const SizedBox(width: 8),
              Text('${AppLocalizations.of(context).paste} (Ctrl+V)'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'select_all',
          child: Row(
            children: [
              const Icon(Icons.select_all, size: 18),
              const SizedBox(width: 8),
              Text('${AppLocalizations.of(context).selectAll} (Ctrl+A)'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleContextMenuAction(value);
    });
  }

  void _handleContextMenuAction(String action) {
    switch (action) {
      case 'copy':
        _copySelection();
        break;
      case 'paste':
        _pasteFromClipboard();
        break;
      case 'select_all':
        _selectAll();
        break;
    }
  }

  void _copySelection() {
    final selection = _controller.selection;
    if (selection == null) return;

    final text = widget.terminal.buffer.getText(selection);
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).copiedToClipboard),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      widget.terminal.paste(text);
      _controller.clearSelection();
    }
  }

  void _selectAll() {
    _controller.setSelection(
      widget.terminal.buffer.createAnchor(
        0,
        widget.terminal.buffer.height - widget.terminal.viewHeight,
      ),
      widget.terminal.buffer.createAnchor(
        widget.terminal.viewWidth,
        widget.terminal.buffer.height - 1,
      ),
      mode: SelectionMode.line,
    );
  }
}
