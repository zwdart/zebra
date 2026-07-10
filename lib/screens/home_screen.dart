import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/ssh_provider.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'connection_form_screen.dart';
import 'terminal_screen.dart';
import 'sftp_screen.dart';
import 'settings_screen.dart';
import 'monitor_screen.dart';
import '../widgets/connection_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectionProvider>().loadConnections();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text(loc.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: loc.settings,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: loc.appTitle,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings, size: 18),
                  tooltip: loc.settings,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: loc.search,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  context.read<ConnectionProvider>().setSearchQuery(v),
            ),
          ),
          Expanded(
            child: Consumer<ConnectionProvider>(
              builder: (ctx, provider, _) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final connections = provider.connections;
                if (connections.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.computer,
                            size: 64, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(loc.noConnections,
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: connections.length,
                  itemBuilder: (ctx, i) {
                    final conn = connections[i];
                    return ConnectionCard(
                      connection: conn,
                      onConnect: () => _connectToServer(context, conn),
                      onEdit: () => _editConnection(context, conn),
                      onDelete: () => _deleteConnection(context, conn),
                      onSftp: () => _openSftp(context, conn),
                      onMonitor: () => _openMonitor(context, conn),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addConnection(context),
        icon: const Icon(Icons.add),
        label: Text(loc.addConnection),
      ),
    );
  }

  void _addConnection(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConnectionFormScreen()),
    );
  }

  void _editConnection(BuildContext context, dynamic conn) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectionFormScreen(connection: conn),
      ),
    );
  }

  void _deleteConnection(BuildContext context, dynamic conn) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.confirmDelete),
        content: Text(loc.confirmDeleteMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () {
              context.read<ConnectionProvider>().deleteConnection(conn.id!);
              Navigator.pop(ctx);
            },
            child: Text(loc.confirm, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _connectToServer(BuildContext context, dynamic conn) async {
    final loc = AppLocalizations.of(context);
    final sshProvider = context.read<SshProvider>();

    if (sshProvider.isConnected) {
      sshProvider.disconnect();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(loc.connecting),
          ],
        ),
      ),
    );

    await sshProvider.connect(conn);
    if (!mounted) return;
    Navigator.of(context).pop();

    if (sshProvider.isConnected) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TerminalScreen()),
      );
    } else if (sshProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${loc.connectionError}: ${sshProvider.error}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _openSftp(BuildContext context, dynamic conn) async {
    final loc = AppLocalizations.of(context);
    final sshProvider = context.read<SshProvider>();

    final needConnect = !sshProvider.isConnected ||
        sshProvider.currentConnection?.id != conn.id;

    if (needConnect) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(loc.connecting),
            ],
          ),
        ),
      );

      await sshProvider.connect(conn);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (!sshProvider.isConnected) {
        if (sshProvider.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.connectionError}: ${sshProvider.error}')),
          );
        }
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SftpScreen()),
    );
  }

  Future<void> _openMonitor(BuildContext context, dynamic conn) async {
    final loc = AppLocalizations.of(context);
    final sshProvider = context.read<SshProvider>();

    final needConnect = !sshProvider.isConnected ||
        sshProvider.currentConnection?.id != conn.id;

    if (needConnect) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(loc.connecting),
            ],
          ),
        ),
      );

      await sshProvider.connect(conn);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (!sshProvider.isConnected) {
        if (sshProvider.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.connectionError}: ${sshProvider.error}')),
          );
        }
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MonitorScreen()),
    );
  }
}
