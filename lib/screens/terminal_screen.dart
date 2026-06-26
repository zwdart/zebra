import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../providers/ssh_provider.dart';
import '../l10n/app_localizations.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  Terminal? _terminal;
  bool _isLoading = true;
  final _focusNode = FocusNode();
  final _terminalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTerminal();
    });
  }

  Future<void> _initTerminal() async {
    final sshProvider = context.read<SshProvider>();
    if (!sshProvider.isConnected) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      _terminal = await sshProvider.sshService.openTerminal(
        cols: 120,
        rows: 30,
      );
      setState(() {
        _isLoading = false;
      });
      _focusNode.requestFocus();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terminal error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final sshProvider = context.watch<SshProvider>();
    final conn = sshProvider.currentConnection;

    return Scaffold(
      appBar: AppBar(
        title: Text('${conn?.name ?? "SSH"} - ${loc.terminal}'),
        actions: [
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _terminal == null
              ? Center(
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
                )
              : _buildTerminal(),
    );
  }

  Widget _buildTerminal() {
    return TerminalView(
      _terminal!,
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

  void _reconnect() async {
    final sshProvider = context.read<SshProvider>();
    final conn = sshProvider.currentConnection;
    if (conn == null) return;

    setState(() => _isLoading = true);
    sshProvider.disconnect();
    await sshProvider.connect(conn);

    if (mounted) {
      if (sshProvider.isConnected) {
        _initTerminal();
      } else {
        setState(() => _isLoading = false);
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
