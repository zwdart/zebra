import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ssh_provider.dart';
import '../l10n/app_localizations.dart';
import 'process_screen.dart';
import 'cleanup_screen.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  Timer? _timer;
  bool _isLoading = true;
  bool _isAutoRefresh = true;
  int _refreshInterval = 3;
  _ServerMetrics? _metrics;
  String? _error;
  int _cpuTicks1 = 0;
  int _cpuTotal1 = 0;
  List<_LoginRecord> _loginHistory = [];
  List<_FailedLoginRecord> _failedLogins = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMetrics());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    final sshProvider = context.read<SshProvider>();
    return sshProvider.sshService.execute(cmd);
  }

  Future<void> _fetchMetrics() async {
    setState(() {
      _isLoading = _metrics == null;
      _error = null;
    });

    try {
      final cmd = StringBuffer();
      cmd.writeln(r'echo "KERNEL:$(uname -s -r -m 2>/dev/null || echo Unknown)"');
      cmd.writeln(r"""echo 'OS:'$(cat /etc/os-release 2>/dev/null | sed -n 's/^PRETTY_NAME=//p' | tr -d '"' || echo Unknown)""");
      cmd.writeln(r'echo "HOSTNAME:$(hostname 2>/dev/null || echo Unknown)"');
      cmd.writeln(r"echo 'CPUINFO:'$(cat /proc/cpuinfo 2>/dev/null | grep -E 'model name|cpu MHz' | head -2)");
      cmd.writeln(r'echo "CPU_CORES:$(nproc 2>/dev/null || echo 1)"');
      cmd.writeln(r"echo 'CPU_STAT:'$(cat /proc/stat 2>/dev/null | head -1 || echo '')");
      cmd.writeln(r"echo 'MEMINFO:'$(free -b 2>/dev/null | awk '/^Mem:/{print $2,$3}' || echo '0 0')");
      cmd.writeln(r"echo 'DISK:'$(df -B1 / 2>/dev/null | awk 'NR==2{print $2,$3,$4,$5}' || echo '0 0 0 0%')");
      cmd.writeln(r"echo 'LOAD:$(cat /proc/loadavg 2>/dev/null || echo 0 0 0)'");
      cmd.writeln(r'echo "PROCS:$(ps -e --no-headers 2>/dev/null | wc -l || echo 0)"');
      cmd.writeln(r"""echo 'NET:'$(cat /proc/net/dev 2>/dev/null | awk 'NR>2{gsub(/:/,"",$1); rx+=$2; tx+=$10}END{print rx,tx}' || echo '0 0')""");
      cmd.writeln(r"echo 'UPTIME:'$(cat /proc/uptime 2>/dev/null | awk '{print $1}' || echo 0)");

      final output = await _exec('LC_ALL=C ${cmd.toString().replaceAll('\n', '; ')}');

      String extract(String key) {
        final marker = '$key:';
        final idx = output.indexOf(marker);
        if (idx < 0) return '';
        final rest = output.substring(idx + marker.length);
        final endIdx = rest.indexOf('\n');
        return (endIdx < 0 ? rest : rest.substring(0, endIdx)).trim();
      }

      final kernelInfo = extract('KERNEL');
      final osName = extract('OS');
      final hostname = extract('HOSTNAME');

      final cpuInfoLines = extract('CPUINFO').split('\n');
      String cpuModel = 'Unknown';
      String cpuMhz = '';
      for (final line in cpuInfoLines) {
        if (line.contains('model name')) {
          cpuModel = line.split(':').skip(1).join(':').trim();
          if (cpuModel.isEmpty) cpuModel = 'Unknown';
        } else if (line.contains('cpu MHz')) {
          cpuMhz = line.split(':').skip(1).join(':').trim();
        }
      }

      final cpuCores = int.tryParse(extract('CPU_CORES')) ?? 1;
      final cpuStatStr = extract('CPU_STAT');

      final memParts = extract('MEMINFO').split(' ');
      final totalMem = int.tryParse(memParts.isNotEmpty ? memParts[0] : '') ?? 0;
      final usedMem = int.tryParse(memParts.length > 1 ? memParts[1] : '') ?? 0;

      final diskParts = extract('DISK').split(' ');
      final loadStr = extract('LOAD');
      final processCount = int.tryParse(extract('PROCS')) ?? 0;
      final netParts = extract('NET').split(' ');
      final uptimeSeconds = double.tryParse(extract('UPTIME')) ?? 0;

      final diskTotal = diskParts.isNotEmpty ? int.tryParse(diskParts[0]) ?? 0 : 0;
      final diskUsed = diskParts.length >= 2 ? int.tryParse(diskParts[1]) ?? 0 : 0;
      final diskAvail = diskParts.length >= 3 ? int.tryParse(diskParts[2]) ?? 0 : 0;
      final diskUsePercent = diskParts.length >= 4 ? diskParts[3] : '0%';

      final loadParts = loadStr.split(' ');
      final load1 = double.tryParse(loadParts.isNotEmpty ? loadParts[0] : '') ?? 0;
      final load5 = double.tryParse(loadParts.length > 1 ? loadParts[1] : '') ?? 0;
      final load15 = double.tryParse(loadParts.length > 2 ? loadParts[2] : '') ?? 0;

      double cpuUsage = 0;
      if (cpuStatStr.startsWith('cpu ')) {
        final nums = cpuStatStr.substring(5).trim().split(RegExp(r'\s+'));
        if (nums.length >= 4) {
          final idle = int.tryParse(nums[3]) ?? 0;
          final total = nums.map((e) => int.tryParse(e) ?? 0).reduce((a, b) => a + b);
          if (_cpuTotal1 > 0) {
            final totalDiff = total - _cpuTotal1;
            final idleDiff = idle - _cpuTicks1;
            if (totalDiff > 0) {
              cpuUsage = ((totalDiff - idleDiff) / totalDiff * 100);
            }
          }
          _cpuTotal1 = total;
          _cpuTicks1 = idle;
        }
      }

      double netRx = 0, netTx = 0;
      if (netParts.length >= 2) {
        netRx = double.tryParse(netParts[0]) ?? 0;
        netTx = double.tryParse(netParts[1]) ?? 0;
      }

      if (mounted) {
        setState(() {
          _metrics = _ServerMetrics(
            hostname: hostname,
            osName: osName,
            kernelInfo: kernelInfo,
            cpuModel: cpuModel,
            cpuCores: cpuCores,
            cpuMhz: cpuMhz,
            cpuUsage: cpuUsage.clamp(0, 100),
            totalMemory: totalMem,
            usedMemory: usedMem,
            totalDisk: diskTotal,
            usedDisk: diskUsed,
            availableDisk: diskAvail,
            diskUsePercent: diskUsePercent,
            load1: load1,
            load5: load5,
            load15: load15,
            uptime: uptimeSeconds,
            processCount: processCount,
            netRx: netRx,
            netTx: netTx,
            fetchedAt: DateTime.now(),
          );
          _isLoading = false;
        });
        _startAutoRefresh();
        _fetchLogins();
        _fetchFailedLogins();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchLogins() async {
    try {
      final output = await _exec('last -F -n 20 2>/dev/null || last -n 20 2>/dev/null || echo ""');
      final lines = output.split('\n');
      final records = <_LoginRecord>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('wtmp') || trimmed.startsWith('reboot')) continue;
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length < 3) continue;

        final user = parts[0];
        if (user == 'wtmp' || user == 'reboot' || user == 'runlevel' || user == 'shutdown') continue;

        String terminal = '';
        String from = '';
        String loginTime = '';
        String duration = '';

        if (trimmed.contains('pts/') || trimmed.contains('tty')) {
          terminal = parts.firstWhere((p) => p.startsWith('pts/') || p.startsWith('tty'), orElse: () => '');
          final termIdx = parts.indexOf(terminal);
          if (termIdx >= 0 && termIdx + 1 < parts.length) {
            from = parts[termIdx + 1];
          }
          final timeParts = parts.sublist(termIdx + 2);
          loginTime = timeParts.take(5).join(' ');
          duration = timeParts.length > 5 ? timeParts.sublist(5).join(' ') : '';
        } else {
          if (parts.length >= 4) {
            terminal = parts[1];
            from = parts[2];
            loginTime = parts.sublist(3).take(5).join(' ');
            duration = parts.length > 8 ? parts.sublist(8).join(' ') : '';
          }
        }

        if (loginTime.isNotEmpty) {
          records.add(_LoginRecord(
            user: user,
            terminal: terminal,
            from: from,
            loginTime: loginTime.trim(),
            duration: duration.trim(),
          ));
        }
      }

      if (mounted) {
        setState(() => _loginHistory = records);
      }
    } catch (_) {}
  }

  Future<void> _fetchFailedLogins() async {
    try {
      final output = await _exec(r"""
        (
          # Try journalctl first
          journalctl -u sshd -u ssh --since "7 days ago" --no-pager -n 500 2>/dev/null | grep -i 'failed\|invalid\|authentication failure'
        ) || (
          # Fallback to auth.log / secure
          grep -i 'failed password\|invalid user\|authentication failure' /var/log/auth.log /var/log/secure 2>/dev/null | tail -500
        ) || (
          # Try lastb
          lastb -F -n 100 2>/dev/null | head -100
        ) || echo ""
""");

      final lines = output.split('\n');
      final records = <_FailedLoginRecord>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        String user = 'unknown';
        String from = 'unknown';
        String time = '';

        if (trimmed.contains('Failed password')) {
          final userMatch = RegExp(r'for (?:invalid user )?(\S+)').firstMatch(trimmed);
          final fromMatch = RegExp(r'from (\S+)').firstMatch(trimmed);
          user = userMatch?.group(1) ?? 'unknown';
          from = fromMatch?.group(1) ?? 'unknown';
          final timeMatch = RegExp(r'^\w+\s+\d+\s+[\d:]+').firstMatch(trimmed);
          if (timeMatch != null) time = timeMatch.group(0)!;
          if (time.isEmpty) {
            final bracketMatch = RegExp(r'(\w+\s+\d+\s+[\d:]+)').firstMatch(trimmed);
            time = bracketMatch?.group(1) ?? '';
          }
        } else if (trimmed.contains('Invalid user')) {
          final userMatch = RegExp(r'Invalid user (\S+)').firstMatch(trimmed);
          final fromMatch = RegExp(r'from (\S+)').firstMatch(trimmed);
          user = userMatch?.group(1) ?? 'unknown';
          from = fromMatch?.group(1) ?? 'unknown';
          final bracketMatch = RegExp(r'(\w+\s+\d+\s+[\d:]+)').firstMatch(trimmed);
          time = bracketMatch?.group(1) ?? '';
        } else if (trimmed.contains('authentication failure')) {
          final userMatch = RegExp(r'rhost=(\S+)').firstMatch(trimmed);
          final fromMatch = RegExp(r'ruser=(\S+)').firstMatch(trimmed);
          from = userMatch?.group(1) ?? 'unknown';
          user = fromMatch?.group(1) ?? 'unknown';
          if (user.isEmpty || user == 'unknown') {
            final altUser = RegExp(r'USER=(\S+)').firstMatch(trimmed);
            user = altUser?.group(1) ?? 'unknown';
          }
          final bracketMatch = RegExp(r'(\w+\s+\d+\s+[\d:]+)').firstMatch(trimmed);
          time = bracketMatch?.group(1) ?? '';
        } else if (trimmed.contains('pts/') || trimmed.contains('tty')) {
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            user = parts[0];
            final termIdx = parts.indexWhere((p) => p.startsWith('pts/') || p.startsWith('tty'));
            if (termIdx >= 0 && termIdx + 1 < parts.length) {
              from = parts[termIdx + 1];
            }
            final timeParts = parts.sublist(termIdx + 1);
            final bracketMatch = RegExp(r'(\w+\s+\d+\s+[\d:]+)').firstMatch(timeParts.join(' '));
            time = bracketMatch?.group(1) ?? '';
          }
        }

        if (user != 'unknown' || from != 'unknown') {
          records.add(_FailedLoginRecord(
            user: user,
            from: from,
            time: time,
          ));
        }
      }

      if (mounted) {
        setState(() => _failedLogins = records);
      }
    } catch (_) {}
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    if (_isAutoRefresh) {
      _timer = Timer.periodic(Duration(seconds: _refreshInterval), (_) {
        _fetchMetrics();
      });
    }
  }

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes;
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  String _formatUptime(double seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$d d $h h $m m';
    if (h > 0) return '$h h $m m';
    return '$m m';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.serverMonitor),
        actions: [
          if (_metrics != null)
            IconButton(
              icon: Icon(_isAutoRefresh ? Icons.pause : Icons.play_arrow),
              tooltip: _isAutoRefresh ? loc.pauseRefresh : loc.autoRefresh,
              onPressed: () {
                setState(() => _isAutoRefresh = !_isAutoRefresh);
                _startAutoRefresh();
              },
            ),
          if (_metrics != null)
            PopupMenuButton<int>(
              icon: const Icon(Icons.timer_outlined),
              tooltip: loc.refreshInterval,
              onSelected: (v) {
                setState(() => _refreshInterval = v);
                _startAutoRefresh();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 1, child: Text('1s')),
                const PopupMenuItem(value: 3, child: Text('3s')),
                const PopupMenuItem(value: 5, child: Text('5s')),
                const PopupMenuItem(value: 10, child: Text('10s')),
                const PopupMenuItem(value: 30, child: Text('30s')),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: loc.refresh,
            onPressed: _fetchMetrics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchMetrics,
                        child: Text(loc.retry),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchMetrics,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildSystemInfoCard(theme),
                      const SizedBox(height: 12),
                      _buildCpuCard(theme),
                      const SizedBox(height: 12),
                      _buildMemoryCard(theme),
                      const SizedBox(height: 12),
                      _buildDiskCard(theme),
                      const SizedBox(height: 12),
                      _buildLoadCard(theme),
                      const SizedBox(height: 12),
                      _buildNetworkCard(theme),
                      const SizedBox(height: 12),
                      _buildProcessCard(theme),
                      const SizedBox(height: 12),
                      _buildLoginCard(theme),
                      const SizedBox(height: 12),
                      _buildFailedLoginCard(theme),
                      const SizedBox(height: 16),
                      Text(
                        '${loc.lastUpdated}: ${_metrics!.fetchedAt.hour.toString().padLeft(2, '0')}:${_metrics!.fetchedAt.minute.toString().padLeft(2, '0')}:${_metrics!.fetchedAt.second.toString().padLeft(2, '0')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSystemInfoCard(ThemeData theme) {
    final m = _metrics!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.computer, AppLocalizations.of(context).systemInfo),
            const Divider(),
            _infoRow(theme, AppLocalizations.of(context).hostname, m.hostname),
            _infoRow(theme, AppLocalizations.of(context).operatingSystem, m.osName),
            _infoRow(theme, AppLocalizations.of(context).kernel, m.kernelInfo),
            _infoRow(theme, AppLocalizations.of(context).cpuModelLabel, m.cpuModel),
            _infoRow(theme, '${AppLocalizations.of(context).cpuCores} (${m.cpuMhz.isNotEmpty ? '${m.cpuMhz} MHz' : ''})', '${m.cpuCores}'),
            _infoRow(theme, AppLocalizations.of(context).uptimeLabel, _formatUptime(m.uptime)),
          ],
        ),
      ),
    );
  }

  Widget _buildCpuCard(ThemeData theme) {
    final m = _metrics!;
    final color = _usageColor(m.cpuUsage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.memory, AppLocalizations.of(context).cpuUsage),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: m.cpuUsage / 100,
                          strokeWidth: 8,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                      Text(
                        '${m.cpuUsage.toStringAsFixed(1)}%',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _metricLabel(theme, AppLocalizations.of(context).cpuCores, '${m.cpuCores}'),
                      const SizedBox(height: 4),
                      if (m.cpuMhz.isNotEmpty)
                        _metricLabel(theme, AppLocalizations.of(context).frequency, '${m.cpuMhz} MHz'),
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

  Widget _buildMemoryCard(ThemeData theme) {
    final m = _metrics!;
    final usage = m.totalMemory > 0 ? m.usedMemory / m.totalMemory * 100 : 0.0;
    final color = _usageColor(usage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.sd_storage, AppLocalizations.of(context).memory),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: usage / 100,
                minHeight: 24,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatBytes(m.usedMemory.toDouble())} / ${_formatBytes(m.totalMemory.toDouble())}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${usage.toStringAsFixed(1)}%',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskCard(ThemeData theme) {
    final m = _metrics!;
    final usage = m.totalDisk > 0 ? m.usedDisk / m.totalDisk * 100 : 0.0;
    final color = _usageColor(usage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.storage, AppLocalizations.of(context).disk),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: usage / 100,
                minHeight: 24,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatBytes(m.usedDisk.toDouble())} / ${_formatBytes(m.totalDisk.toDouble())}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  m.diskUsePercent,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${AppLocalizations.of(context).available}: ${_formatBytes(m.availableDisk.toDouble())}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CleanupScreen()));
                },
                icon: const Icon(Icons.cleaning_services, size: 16),
                label: Text(AppLocalizations.of(context).diskCleanup),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadCard(ThemeData theme) {
    final m = _metrics!;
    final cores = m.cpuCores.toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.speed, AppLocalizations.of(context).loadAverage),
            const SizedBox(height: 12),
            Row(
              children: [
                _loadIndicator(theme, '1 min', m.load1, cores),
                const SizedBox(width: 16),
                _loadIndicator(theme, '5 min', m.load5, cores),
                const SizedBox(width: 16),
                _loadIndicator(theme, '15 min', m.load15, cores),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadIndicator(ThemeData theme, String label, double value, double cores) {
    final ratio = cores > 0 ? (value / cores).clamp(0.0, 1.0) : 0.0;
    final color = _usageColor(ratio * 100);
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                Text(
                  value.toStringAsFixed(1),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildNetworkCard(ThemeData theme) {
    final m = _metrics!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.network_check, AppLocalizations.of(context).network),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _networkMetric(
                    theme,
                    Icons.arrow_downward,
                    AppLocalizations.of(context).received,
                    _formatBytes(m.netRx),
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _networkMetric(
                    theme,
                    Icons.arrow_upward,
                    AppLocalizations.of(context).sent,
                    _formatBytes(m.netTx),
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _networkMetric(ThemeData theme, IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildProcessCard(ThemeData theme) {
    final m = _metrics!;
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProcessScreen()),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(theme, Icons.list_alt, AppLocalizations.of(context).processes),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.category, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${m.processCount}',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).runningProcesses, style: theme.textTheme.bodyMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard(ThemeData theme) {
    final loc = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.history, loc.recentLogins),
            if (_loginHistory.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    loc.noLoginHistory,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              ..._loginHistory.take(10).map((r) => _loginRow(r, theme)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loginRow(_LoginRecord r, ThemeData theme) {
    final isCurrentSession = r.duration.toLowerCase().contains('still') ||
        r.duration.toLowerCase().contains('online');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isCurrentSession ? Icons.circle : Icons.circle_outlined,
            size: 8,
            color: isCurrentSession ? Colors.green : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              r.user,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lan, size: 12, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              r.from,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.loginTime,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (r.duration.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isCurrentSession ? Colors.green : theme.colorScheme.outline).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                r.duration,
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFailedLoginCard(ThemeData theme) {
    final loc = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, Icons.warning_amber, loc.failedLogins),
            if (_failedLogins.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    loc.noFailedLogins,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              ..._failedLogins.take(15).map((r) => _failedLoginRow(r, theme)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _failedLoginRow(_FailedLoginRecord r, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.close, size: 10, color: Colors.red),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              r.user,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lan, size: 12, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              r.from,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (r.time.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(
                r.time,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _metricLabel(ThemeData theme, String label, String value) {
    return Row(
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(width: 4),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Color _usageColor(double percent) {
    if (percent >= 90) return Colors.red;
    if (percent >= 70) return Colors.orange;
    if (percent >= 50) return Colors.amber;
    return Colors.green;
  }
}

class _ServerMetrics {
  final String hostname;
  final String osName;
  final String kernelInfo;
  final String cpuModel;
  final int cpuCores;
  final String cpuMhz;
  final double cpuUsage;
  final int totalMemory;
  final int usedMemory;
  final int totalDisk;
  final int usedDisk;
  final int availableDisk;
  final String diskUsePercent;
  final double load1;
  final double load5;
  final double load15;
  final double uptime;
  final int processCount;
  final double netRx;
  final double netTx;
  final DateTime fetchedAt;

  _ServerMetrics({
    required this.hostname,
    required this.osName,
    required this.kernelInfo,
    required this.cpuModel,
    required this.cpuCores,
    required this.cpuMhz,
    required this.cpuUsage,
    required this.totalMemory,
    required this.usedMemory,
    required this.totalDisk,
    required this.usedDisk,
    required this.availableDisk,
    required this.diskUsePercent,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.uptime,
    required this.processCount,
    required this.netRx,
    required this.netTx,
    required this.fetchedAt,
  });
}

class _LoginRecord {
  final String user;
  final String terminal;
  final String from;
  final String loginTime;
  final String duration;

  _LoginRecord({
    required this.user,
    required this.terminal,
    required this.from,
    required this.loginTime,
    required this.duration,
  });
}

class _FailedLoginRecord {
  final String user;
  final String from;
  final String time;

  _FailedLoginRecord({
    required this.user,
    required this.from,
    required this.time,
  });
}
