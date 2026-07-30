import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_service.dart';
import '../models/ssh_connection.dart';
import '../providers/connection_provider.dart';
import '../providers/ssh_provider.dart';
import '../utils/zebra_paths.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'connection_form_screen.dart';
import 'terminal_screen.dart';
import 'sftp_screen.dart';
import 'monitor_screen.dart';
import 'rss/rss_explore_screen.dart';
import '../widgets/connection_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text(loc.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: loc.addConnection,
            onPressed: () => _addConnection(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export_csv') _exportCsv(context);
              else if (v == 'import_csv') _importCsv(context);
              else if (v == 'discover') _openDiscover(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export_csv', child: Text(loc.exportCsv)),
              PopupMenuItem(value: 'import_csv', child: Text(loc.importCsv)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'discover', child: Text(loc.rssExplore)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: loc.appTitle,
              showBackButton: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: loc.addConnection,
                  onPressed: () => _addConnection(context),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'export_csv') _exportCsv(context);
                    else if (v == 'import_csv') _importCsv(context);
                    else if (v == 'discover') _openDiscover(context);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'export_csv', child: Text(loc.exportCsv)),
                    PopupMenuItem(value: 'import_csv', child: Text(loc.importCsv)),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'discover', child: Text(loc.rssExplore)),
                  ],
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

    );
  }

  void _addConnection(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConnectionFormScreen()),
    );
  }

  void _openDiscover(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RssExploreScreen(initialTab: 1)),
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

  String _csvEscape(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _exportCsv(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    try {
      final connections = DatabaseService.getAllConnections();
      final csv = StringBuffer('name,host,port,username,auth_type,password,private_key_path,passphrase,remark\n');
      for (final c in connections) {
        csv.write('${_csvEscape(c.name)},${_csvEscape(c.host)},${c.port},${_csvEscape(c.username)},${_csvEscape(c.authType)},${_csvEscape(c.password ?? '')},${_csvEscape(c.privateKeyPath ?? '')},${_csvEscape(c.passphrase ?? '')},${_csvEscape(c.remark ?? '')}\n');
      }

      final ts = _timestamp();
      final filename = 'ssh_connections_$ts.csv';
      final path = await ZebraPaths.filePath('ssh', filename);
      final file = File(path);
      await file.writeAsString(csv.toString());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(loc.exportCsv),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.exportSuccess),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    path,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(loc.close),
              ),
              FilledButton(
                onPressed: () {
                  Share.shareXFiles([XFile(path)], subject: filename);
                  Navigator.pop(context);
                },
                child: Text(loc.share),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.exportFailed}: $e')),
        );
      }
    }
  }

  Future<void> _importCsv(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    try {
      final file = File(result.files.first.path!);
      final csvContent = await file.readAsString();
      final lines = csvContent.split('\n').where((l) => l.trim().isNotEmpty).toList();
      var imported = 0;

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final values = _parseCsvLine(line);
        if (values.length < 4) continue;

        final conn = SshConnection(
          name: values[0],
          host: values[1],
          port: int.tryParse(values[2]) ?? 22,
          username: values[3],
          authType: values.length > 4 ? values[4] : 'password',
          password: values.length > 5 ? values[5] : null,
          privateKeyPath: values.length > 6 ? values[6] : null,
          passphrase: values.length > 7 ? values[7] : null,
          remark: values.length > 8 ? values[8] : null,
        );
        DatabaseService.insertConnection(conn);
        imported++;
      }

      if (context.mounted) {
        context.read<ConnectionProvider>().loadConnections();
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.importSuccess} ($imported)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.importFailed}: $e')),
        );
      }
    }
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }
}
