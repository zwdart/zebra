import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/monitor_provider.dart';
import '../l10n/app_localizations.dart';
import 'process_screen.dart';
import 'cleanup_screen.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MonitorProvider>().fetchMetrics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.serverMonitor),
        actions: [
          Consumer<MonitorProvider>(
            builder: (_, provider, __) {
              if (provider.metrics == null) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(provider.isAutoRefresh ? Icons.pause : Icons.play_arrow),
                tooltip: provider.isAutoRefresh ? loc.pauseRefresh : loc.autoRefresh,
                onPressed: () => provider.setAutoRefresh(!provider.isAutoRefresh),
              );
            },
          ),
          Consumer<MonitorProvider>(
            builder: (_, provider, __) {
              if (provider.metrics == null) return const SizedBox.shrink();
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
            icon: const Icon(Icons.refresh),
            tooltip: loc.refresh,
            onPressed: () => context.read<MonitorProvider>().fetchMetrics(),
          ),
        ],
      ),
      body: Consumer<MonitorProvider>(
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
                    onPressed: () => provider.fetchMetrics(),
                    child: Text(loc.retry),
                  ),
                ],
              ),
            );
          }

          final m = provider.metrics!;
          final loc2 = AppLocalizations.of(context);

          return RefreshIndicator(
            onRefresh: () => provider.fetchMetrics(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SystemInfoCard(metrics: m),
                const SizedBox(height: 12),
                _CpuCard(metrics: m),
                const SizedBox(height: 12),
                _MemoryCard(metrics: m),
                const SizedBox(height: 12),
                _DiskCard(metrics: m),
                const SizedBox(height: 12),
                _LoadCard(metrics: m),
                const SizedBox(height: 12),
                _NetworkCard(metrics: m),
                const SizedBox(height: 12),
                _ProcessCard(processCount: m.processCount),
                const SizedBox(height: 12),
                _LoginCard(loginHistory: provider.loginHistory),
                const SizedBox(height: 12),
                _FailedLoginCard(failedLogins: provider.failedLogins),
                const SizedBox(height: 16),
                Text(
                  '${loc2.lastUpdated}: ${m.fetchedAt.hour.toString().padLeft(2, '0')}:${m.fetchedAt.minute.toString().padLeft(2, '0')}:${m.fetchedAt.second.toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _MetricLabel extends StatelessWidget {
  final String label;
  final String value;
  const _MetricLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(width: 4),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _SystemInfoCard extends StatelessWidget {
  final ServerMetrics metrics;
  const _SystemInfoCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final loc = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.computer, title: loc.systemInfo),
            const Divider(),
            _InfoRow(label: loc.hostname, value: m.hostname),
            _InfoRow(label: loc.operatingSystem, value: m.osName),
            _InfoRow(label: loc.kernel, value: m.kernelInfo),
            _InfoRow(label: loc.cpuModelLabel, value: m.cpuModel),
            _InfoRow(label: '${loc.cpuCores} (${m.cpuMhz.isNotEmpty ? '${m.cpuMhz} MHz' : ''})', value: '${m.cpuCores}'),
            _InfoRow(label: loc.uptimeLabel, value: MonitorProvider.formatUptime(m.uptime)),
          ],
        ),
      ),
    );
  }
}

class _CpuCard extends StatelessWidget {
  final ServerMetrics metrics;
  const _CpuCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final color = MonitorProvider.usageColor(m.cpuUsage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.memory, title: AppLocalizations.of(context).cpuUsage),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 80, height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 80, height: 80,
                        child: CircularProgressIndicator(
                          value: m.cpuUsage / 100, strokeWidth: 8,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                      Text('${m.cpuUsage.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetricLabel(label: AppLocalizations.of(context).cpuCores, value: '${m.cpuCores}'),
                      const SizedBox(height: 4),
                      if (m.cpuMhz.isNotEmpty)
                        _MetricLabel(label: AppLocalizations.of(context).frequency, value: '${m.cpuMhz} MHz'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final ServerMetrics metrics;
  const _MemoryCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final usage = m.totalMemory > 0 ? m.usedMemory / m.totalMemory * 100 : 0.0;
    final color = MonitorProvider.usageColor(usage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.sd_storage, title: AppLocalizations.of(context).memory),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: usage / 100, minHeight: 24,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${MonitorProvider.formatBytes(m.usedMemory.toDouble())} / ${MonitorProvider.formatBytes(m.totalMemory.toDouble())}'),
                Text('${usage.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiskCard extends StatelessWidget {
  final ServerMetrics metrics;
  const _DiskCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final usage = m.totalDisk > 0 ? m.usedDisk / m.totalDisk * 100 : 0.0;
    final color = MonitorProvider.usageColor(usage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.storage, title: AppLocalizations.of(context).disk),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: usage / 100, minHeight: 24,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${MonitorProvider.formatBytes(m.usedDisk.toDouble())} / ${MonitorProvider.formatBytes(m.totalDisk.toDouble())}'),
                Text(m.diskUsePercent, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${AppLocalizations.of(context).available}: ${MonitorProvider.formatBytes(m.availableDisk.toDouble())}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CleanupScreen())),
                icon: const Icon(Icons.cleaning_services, size: 16),
                label: Text(AppLocalizations.of(context).diskCleanup),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadCard extends StatelessWidget {
  final ServerMetrics metrics;
  const _LoadCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final cores = m.cpuCores.toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.speed, title: AppLocalizations.of(context).loadAverage),
            const SizedBox(height: 12),
            Row(
              children: [
                _LoadIndicator(label: '1 min', value: m.load1, cores: cores),
                const SizedBox(width: 16),
                _LoadIndicator(label: '5 min', value: m.load5, cores: cores),
                const SizedBox(width: 16),
                _LoadIndicator(label: '15 min', value: m.load15, cores: cores),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadIndicator extends StatelessWidget {
  final String label;
  final double value;
  final double cores;
  const _LoadIndicator({required this.label, required this.value, required this.cores});

  @override
  Widget build(BuildContext context) {
    final ratio = cores > 0 ? (value / cores).clamp(0.0, 1.0) : 0.0;
    final color = MonitorProvider.usageColor(ratio * 100);
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 56, height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56, height: 56,
                  child: CircularProgressIndicator(
                    value: ratio, strokeWidth: 6,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                Text(value.toStringAsFixed(1), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final ServerMetrics metrics;
  const _NetworkCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.network_check, title: AppLocalizations.of(context).network),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _NetworkMetric(icon: Icons.arrow_downward, label: AppLocalizations.of(context).received, value: MonitorProvider.formatBytes(m.netRx), color: Colors.green)),
                const SizedBox(width: 16),
                Expanded(child: _NetworkMetric(icon: Icons.arrow_upward, label: AppLocalizations.of(context).sent, value: MonitorProvider.formatBytes(m.netTx), color: Colors.blue)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _NetworkMetric({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ProcessCard extends StatelessWidget {
  final int processCount;
  const _ProcessCard({required this.processCount});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProcessScreen())),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(icon: Icons.list_alt, title: AppLocalizations.of(context).processes),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.category, color: Theme.of(context).colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('$processCount', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).runningProcesses),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final List<LoginRecord> loginHistory;
  const _LoginCard({required this.loginHistory});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.history, title: loc.recentLogins),
            if (loginHistory.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text(loc.noLoginHistory, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline))),
              )
            else ...[
              const SizedBox(height: 8),
              ...loginHistory.take(10).map((r) => _LoginRow(record: r)),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoginRow extends StatelessWidget {
  final LoginRecord record;
  const _LoginRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final isOnline = r.duration.toLowerCase().contains('still') || r.duration.toLowerCase().contains('online');
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(isOnline ? Icons.circle : Icons.circle_outlined, size: 8, color: isOnline ? Colors.green : theme.colorScheme.outline),
          const SizedBox(width: 8),
          SizedBox(width: 60, child: Text(r.user, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Icon(Icons.lan, size: 12, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Expanded(child: Text(r.from, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Expanded(child: Text(r.loginTime, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
          if (r.duration.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: (isOnline ? Colors.green : theme.colorScheme.outline).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(r.duration, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10)),
            ),
          ],
        ],
      ),
    );
  }
}

class _FailedLoginCard extends StatelessWidget {
  final List<FailedLoginRecord> failedLogins;
  const _FailedLoginCard({required this.failedLogins});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.warning_amber, title: loc.failedLogins),
            if (failedLogins.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text(loc.noFailedLogins, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline))),
              )
            else ...[
              const SizedBox(height: 8),
              ...failedLogins.take(15).map((r) => _FailedLoginRow(record: r)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FailedLoginRow extends StatelessWidget {
  final FailedLoginRecord record;
  const _FailedLoginRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.close, size: 10, color: Colors.red),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(r.user, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Icon(Icons.lan, size: 12, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Expanded(child: Text(r.from, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis)),
          if (r.time.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(flex: 2, child: Text(r.time, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontSize: 11), overflow: TextOverflow.ellipsis)),
          ],
        ],
      ),
    );
  }
}
