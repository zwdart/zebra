import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cleanup_provider.dart';
import '../l10n/app_localizations.dart';

class CleanupScreen extends StatefulWidget {
  const CleanupScreen({super.key});

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends State<CleanupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CleanupProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.diskCleanup),
        actions: [
          Consumer<CleanupProvider>(
            builder: (_, provider, __) {
              if (provider.isLoading || provider.tasks.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: loc.cleanAll,
                onPressed: provider.isCleaning ? null : () => _cleanAll(context),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: loc.refresh,
            onPressed: () => context.read<CleanupProvider>().init(),
          ),
        ],
      ),
      body: Consumer<CleanupProvider>(
        builder: (_, provider, __) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());
          if (provider.error != null && provider.tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(provider.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => provider.init(), child: Text(loc.retry)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(totalSize: provider.totalSize),
              const SizedBox(height: 16),
              _SectionTitle(icon: Icons.cleaning_services, title: loc.quickClean),
              const SizedBox(height: 8),
              ...provider.tasks.map((t) => _TaskCard(task: t)),
              const SizedBox(height: 16),
              _SectionTitle(icon: Icons.folder_open, title: loc.tempFileBrowser),
              const SizedBox(height: 8),
              _FileBrowser(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _cleanAll(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = context.read<CleanupProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_sweep, color: theme.colorScheme.primary, size: 48),
        title: Text(loc.cleanAll),
        content: Text(loc.cleanAllMsgParam(CleanupProvider.formatBytes(provider.totalSize))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.clean, style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await provider.cleanAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.cleanCompleted(loc.quickClean))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.cleanFailed}: $e')));
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int totalSize;
  const _SummaryCard({required this.totalSize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.storage, color: theme.colorScheme.onPrimaryContainer, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context).totalCleanable, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                  const SizedBox(height: 4),
                  Text(
                    CleanupProvider.formatBytes(totalSize),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final CleanTask task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = context.read<CleanupProvider>();
    final totalSize = provider.totalSize;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: CleanupProvider.usageColor(totalSize > 0 ? task.sizeBytes / totalSize * 100 : 0).withValues(alpha: 0.15),
          child: Icon(CleanupProvider.taskIcon(task.id), color: CleanupProvider.usageColor(totalSize > 0 ? task.sizeBytes / totalSize * 100 : 0), size: 20),
        ),
        title: Text(task.label, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          '${task.detail}${task.count != null ? ' (${task.count} items)' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(
                CleanupProvider.formatBytes(task.sizeBytes),
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: provider.isCleaning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cleaning_services, size: 20),
              tooltip: loc.clean,
              onPressed: provider.isCleaning ? null : () => _executeClean(context, task),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeClean(BuildContext context, CleanTask task) async {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = context.read<CleanupProvider>();

    if (task.confirmRequired) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 48),
          title: Text(loc.confirmClean),
          content: Text('${task.label}\n${task.detail}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.clean, style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await provider.executeClean(task);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.cleanCompleted(task.label))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.cleanFailed}: $e')));
      }
    }
  }
}

class _FileBrowser extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Consumer<CleanupProvider>(
      builder: (_, provider, __) {
        return Column(
          children: [
            if (!provider.isScanningFiles && provider.junkFiles.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.search),
                  title: Text(loc.scanTempFiles),
                  subtitle: Text(loc.scanTempFilesDesc),
                  trailing: ElevatedButton(
                    onPressed: () => provider.scanJunkFiles(),
                    child: Text(loc.scan),
                  ),
                ),
              ),
            if (provider.isScanningFiles)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Scanning...'),
                    ],
                  ),
                ),
              ),
            if (!provider.isScanningFiles && provider.junkFiles.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Checkbox(
                        value: provider.allSelected,
                        tristate: provider.someSelected,
                        onChanged: (v) {
                          if (v == true) {
                            provider.selectAll();
                          } else {
                            provider.deselectAll();
                          }
                        },
                      ),
                      Text(loc.selectAll),
                      const Spacer(),
                      Text('${provider.selectedFiles.length}/${provider.junkFiles.length}', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 12),
                      if (provider.selectedFiles.isNotEmpty)
                        FilledButton.icon(
                          onPressed: provider.isCleaning ? null : () => _deleteSelected(context),
                          icon: const Icon(Icons.delete, size: 16),
                          label: Text(loc.delete),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: loc.rescan,
                        onPressed: () => provider.scanJunkFiles(),
                      ),
                    ],
                  ),
                ),
              ),
              ...provider.junkFiles.map((f) => _FileTile(file: f)),
            ],
          ],
        );
      },
    );
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final provider = context.read<CleanupProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.confirmDeleteSelected),
        content: Text(loc.confirmDeleteSelectedMsg(provider.selectedFiles.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await provider.deleteSelectedFiles();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.deletedFiles(provider.selectedFiles.length))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.deleteFailed}: $e')));
      }
    }
  }
}

class _FileTile extends StatelessWidget {
  final JunkFile file;
  const _FileTile({required this.file});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<CleanupProvider>();
    final isSelected = provider.selectedFiles.contains(file.path);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (v) {
          if (v == true) {
            provider.selectFile(file.path);
          } else {
            provider.deselectFile(file.path);
          }
        },
        title: Text(file.path.split('/').last, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          file.path,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontFamily: 'monospace', fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        secondary: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: CleanupProvider.categoryColor(file.category).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
          child: Text(
            CleanupProvider.formatBytes(file.sizeBytes),
            style: theme.textTheme.labelSmall?.copyWith(color: CleanupProvider.categoryColor(file.category), fontWeight: FontWeight.bold),
          ),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
