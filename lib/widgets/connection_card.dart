import 'package:flutter/material.dart';
import '../models/ssh_connection.dart';

class ConnectionCard extends StatelessWidget {
  final SshConnection connection;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSftp;
  final VoidCallback? onMonitor;

  const ConnectionCard({
    super.key,
    required this.connection,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
    this.onSftp,
    this.onMonitor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onConnect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.computer,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connection.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${connection.username}@${connection.host}:${connection.port}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'connect':
                          onConnect();
                          break;
                        case 'terminal':
                          onConnect();
                          break;
                        case 'sftp':
                          onSftp?.call();
                          break;
                        case 'monitor':
                          onMonitor?.call();
                          break;
                        case 'edit':
                          onEdit();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'connect', child: Text('Connect')),
                      const PopupMenuItem(value: 'sftp', child: Text('SFTP')),
                      PopupMenuItem(value: 'monitor', child: Text('Monitor')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete',
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    ],
                  ),
                ],
              ),
              if (connection.remark != null && connection.remark!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  connection.remark!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    connection.authType == 'key' ? Icons.key : Icons.lock,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    connection.authType == 'key' ? 'Key' : 'Password',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
