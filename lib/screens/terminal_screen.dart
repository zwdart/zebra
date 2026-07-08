import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../providers/ssh_provider.dart';
import '../l10n/app_localizations.dart';
import 'monitor_screen.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFirstTab();
    });
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
      appBar: AppBar(
        title: Text('${conn?.name ?? "SSH"} - ${loc.terminal}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Tab',
            onPressed: () => _addTab(),
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
            onPressed: () => _openSftp(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect',
            onPressed: _reconnect,
          ),
        ],
      ),
      body: _buildBody(sessions, sshProvider),
    );
  }

  Widget _buildBody(List sessions, SshProvider sshProvider) {
    final loc = AppLocalizations.of(context);

    if (!sshProvider.isConnected) {
      return Center(
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
      );
    }

    if (sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Tab bar
        _buildTabBar(sessions, sshProvider),
        // Terminal content
        Expanded(
          child: _buildActiveTerminal(sshProvider),
        ),
      ],
    );
  }

  Widget _buildTabBar(List sessions, SshProvider sshProvider) {
    return Container(
      height: 40,
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isActive = index == sshProvider.activeSessionIndex;

                return GestureDetector(
                  onTap: () => sshProvider.switchSession(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                        bottom: BorderSide(
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
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
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          session.label,
                          style: TextStyle(
                            fontSize: 13,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (sessions.length > 1)
                          GestureDetector(
                            onTap: () {
                              sshProvider.closeTerminalSession(index);
                            },
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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
            const Text('Terminal not available'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _reconnect,
              child: const Text('Retry'),
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

  void _openSftp() {
    Navigator.pushNamed(context, '/sftp');
  }
}

class _TerminalWidget extends StatefulWidget {
  final Terminal terminal;

  const _TerminalWidget({required this.terminal, super.key});

  @override
  State<_TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<_TerminalWidget> {
  final _focusNode = FocusNode();
  final _terminalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      widget.terminal,
      key: _terminalKey,
      focusNode: _focusNode,
      autofocus: true,
      hardwareKeyboardOnly: true,
      textStyle: TerminalStyle(
        fontSize: 14,
        fontFamily: Platform.isWindows ? 'Consolas' : 'monospace',
      ),
    );
  }
}
