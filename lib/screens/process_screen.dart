import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/process_provider.dart';
import '../l10n/app_localizations.dart';

class ProcessScreen extends StatefulWidget {
  const ProcessScreen({super.key});

  @override
  State<ProcessScreen> createState() => _ProcessScreenState();
}

class _ProcessScreenState extends State<ProcessScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ProcessProvider>();
      provider.fetchProcesses();
      provider.startAutoRefresh();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.processList),
        actions: [
          Consumer<ProcessProvider>(
            builder: (_, provider, __) {
              if (provider.processes.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(provider.isAutoRefresh ? Icons.pause : Icons.play_arrow),
                tooltip: provider.isAutoRefresh ? loc.pauseRefresh : loc.autoRefresh,
                onPressed: () => provider.setAutoRefresh(!provider.isAutoRefresh),
              );
            },
          ),
          Consumer<ProcessProvider>(
            builder: (_, provider, __) {
              if (provider.processes.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<int>(
                icon: const Icon(Icons.timer_outlined),
                tooltip: loc.refreshInterval,
                onSelected: (v) => provider.setRefreshInterval(v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 1, child: Text('1s')),
                  const PopupMenuItem(value: 3, child: Text('3s')),
                  const PopupMenuItem(value: 5, child: Text('5s')),
                  const PopupMenuItem(value: 10, child: Text('10s')),
                  const PopupMenuItem(value: 30, child: Text('30s')),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: loc.sort,
            onPressed: () => _showSortDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: loc.refresh,
            onPressed: () => context.read<ProcessProvider>().fetchProcesses(),
          ),
        ],
      ),
      body: Consumer<ProcessProvider>(
        builder: (_, provider, __) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());
          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(provider.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.fetchProcesses(),
                    child: Text(loc.retry),
                  ),
                ],
              ),
            );
          }

          final filtered = provider.filteredProcesses;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: loc.searchProcesses,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: provider.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              provider.setSearchQuery('');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => provider.setSearchQuery(v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text('${filtered.length} / ${provider.processes.length}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    const Spacer(),
                    ActionChip(
                      avatar: Icon(provider.sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                      label: Text(_sortByLabel(loc, provider.sortBy)),
                      onPressed: () => provider.toggleSortOrder(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => provider.fetchProcesses(),
                  child: filtered.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 80),
                              child: Center(
                                child: Text(loc.noProcessesFound, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) => _ProcessTile(process: filtered[i]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _sortByLabel(AppLocalizations loc, String sortBy) {
    switch (sortBy) {
      case 'cpu': return 'CPU%';
      case 'mem': return 'MEM%';
      case 'rss': return loc.memSize;
      case 'pid': return 'PID';
      case 'user': return loc.user;
      default: return 'CPU%';
    }
  }

  void _showSortDialog(BuildContext context) {
    final provider = context.read<ProcessProvider>();
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.sortBy),
        children: [
          SimpleDialogOption(onPressed: () { provider.setSortBy('cpu'); Navigator.pop(ctx); }, child: Text(loc.sortByCpu)),
          SimpleDialogOption(onPressed: () { provider.setSortBy('mem'); Navigator.pop(ctx); }, child: Text(loc.sortByMem)),
          SimpleDialogOption(onPressed: () { provider.setSortBy('rss'); Navigator.pop(ctx); }, child: Text(loc.sortByMemSize)),
          SimpleDialogOption(onPressed: () { provider.setSortBy('pid'); Navigator.pop(ctx); }, child: Text(loc.sortByPid)),
          SimpleDialogOption(onPressed: () { provider.setSortBy('user'); Navigator.pop(ctx); }, child: Text(loc.sortByUser)),
        ],
      ),
    );
  }
}

class _ProcessTile extends StatelessWidget {
  final ProcessInfo process;
  const _ProcessTile({required this.process});

  @override
  Widget build(BuildContext context) {
    final proc = process;
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    final cpuColor = ProcessProvider.usageColor(proc.cpu);
    final memColor = ProcessProvider.usageColor(proc.mem);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: SizedBox(
          width: 48, height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(
                  value: proc.cpu / 100, strokeWidth: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(cpuColor),
                ),
              ),
              Text(proc.cpu.toStringAsFixed(1), style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        title: Text(
          proc.command.length > 60 ? '${proc.command.substring(0, 60)}...' : proc.command,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            _tag(theme, 'PID ${proc.pid}', theme.colorScheme.primary),
            const SizedBox(width: 4),
            _tag(theme, proc.user, theme.colorScheme.secondary),
            const SizedBox(width: 4),
            _tag(theme, 'CPU ${proc.cpu.toStringAsFixed(1)}%', cpuColor),
            const SizedBox(width: 4),
            _tag(theme, 'MEM ${proc.mem.toStringAsFixed(1)}%', memColor),
            const SizedBox(width: 4),
            _tag(theme, ProcessProvider.formatMem(proc.rss), theme.colorScheme.tertiary),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, color: proc.isSystem ? theme.colorScheme.error : null),
          tooltip: proc.isSystem ? loc.killSystemProcess : loc.killProcess,
          onPressed: () => _killProcess(context, proc),
        ),
      ),
    );
  }

  Future<void> _killProcess(BuildContext context, ProcessInfo proc) async {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (proc.isSystem) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 48),
          title: Text(loc.confirmKillSystemProcess),
          content: Text(loc.confirmKillSystemProcessMsg(proc.pid, proc.user)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.kill, style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await context.read<ProcessProvider>().killProcess(proc);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.processSentSignal(proc.pid))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.killFailed}: $e')));
      }
    }
  }

  Widget _tag(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: color, fontSize: 10)),
    );
  }
}
