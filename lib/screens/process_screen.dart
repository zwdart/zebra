import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ssh_provider.dart';
import '../l10n/app_localizations.dart';

class ProcessScreen extends StatefulWidget {
  const ProcessScreen({super.key});

  @override
  State<ProcessScreen> createState() => _ProcessScreenState();
}

class _ProcessScreenState extends State<ProcessScreen> {
  Timer? _timer;
  bool _isLoading = true;
  bool _isAutoRefresh = true;
  int _refreshInterval = 5;
  List<_ProcessInfo> _processes = [];
  String? _error;
  String _sortBy = 'cpu';
  bool _sortAsc = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const _systemUsers = {
    'root', 'daemon', 'bin', 'sys', 'sync', 'games', 'man', 'lp',
    'mail', 'news', 'uucp', 'proxy', 'www-data', 'backup', 'list',
    'irc', 'gnats', 'nobody', 'systemd-network', 'systemd-resolve',
    'syslog', 'messagebus', 'sshd', 'polkitd', 'chrony', 'dbus',
    'tss', 'usbmuxd', 'geoclue', 'tcpdump', 'avahi', 'rtkit',
    'colord', 'gdm', 'gnome-shell', 'power', 'snapd', 'lxd',
  };

  static const _systemBinaries = {
    '/sbin', '/usr/sbin', '/usr/local/sbin', '/lib/systemd',
    '/usr/lib/systemd', '/usr/bin', '/bin', '/usr/lib',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProcesses());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    final sshProvider = context.read<SshProvider>();
    return sshProvider.sshService.execute(cmd);
  }

  Future<void> _fetchProcesses() async {
    setState(() {
      _isLoading = _processes.isEmpty;
      _error = null;
    });

    try {
      final output = await _exec(
        r"ps aux --sort=-pcpu 2>/dev/null || ps aux 2>/dev/null || echo 'ERROR'",
      );

      if (output.trim() == 'ERROR' || output.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Failed to list processes';
            _isLoading = false;
          });
        }
        return;
      }

      final lines = output.split('\n');
      final procs = <_ProcessInfo>[];

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 11) continue;

        final pid = int.tryParse(parts[1]);
        if (pid == null) continue;

        final user = parts[0];
        final cpu = double.tryParse(parts[2]) ?? 0;
        final mem = double.tryParse(parts[3]) ?? 0;
        final vsz = int.tryParse(parts[4]) ?? 0;
        final rss = int.tryParse(parts[5]) ?? 0;
        final stat = parts[7];
        final start = parts[8];
        final time = parts[9];
        final command = parts.sublist(10).join(' ');

        procs.add(_ProcessInfo(
          user: user,
          pid: pid,
          cpu: cpu,
          mem: mem,
          vsz: vsz,
          rss: rss,
          stat: stat,
          start: start,
          time: time,
          command: command,
          isSystem: _isSystemProcess(user, command),
        ));
      }

      if (mounted) {
        setState(() {
          _processes = procs;
          _isLoading = false;
        });
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

  bool _isSystemProcess(String user, String command) {
    if (_systemUsers.contains(user)) return true;
    final exe = command.split(' ').first;
    for (final prefix in _systemBinaries) {
      if (exe.startsWith(prefix)) return true;
    }
    return false;
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    if (_isAutoRefresh) {
      _timer = Timer.periodic(Duration(seconds: _refreshInterval), (_) {
        _fetchProcesses();
      });
    }
  }

  List<_ProcessInfo> get _filtered {
    var list = _processes.where((p) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.command.toLowerCase().contains(q) ||
          p.user.toLowerCase().contains(q) ||
          p.pid.toString().contains(q);
    }).toList();

    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'pid':
          cmp = a.pid.compareTo(b.pid);
          break;
        case 'user':
          cmp = a.user.compareTo(b.user);
          break;
        case 'cpu':
          cmp = a.cpu.compareTo(b.cpu);
          break;
        case 'mem':
          cmp = a.mem.compareTo(b.mem);
          break;
        case 'rss':
          cmp = a.rss.compareTo(b.rss);
          break;
        default:
          cmp = a.cpu.compareTo(b.cpu);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  String _formatMem(int kb) {
    if (kb >= 1048576) return '${(kb / 1048576).toStringAsFixed(1)} G';
    if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(1)} M';
    return '$kb K';
  }

  Future<void> _killProcess(_ProcessInfo proc) async {
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.cancel),
            ),
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
      await _exec('kill -15 ${proc.pid} 2>/dev/null');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.processSentSignal(proc.pid))),
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
      _fetchProcesses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.killFailed}: $e')),
        );
      }
    }
  }

  void _showSortDialog() {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.sortBy),
        children: [
          SimpleDialogOption(
            onPressed: () { setState(() => _sortBy = 'cpu'); Navigator.pop(ctx); },
            child: Text(loc.sortByCpu),
          ),
          SimpleDialogOption(
            onPressed: () { setState(() => _sortBy = 'mem'); Navigator.pop(ctx); },
            child: Text(loc.sortByMem),
          ),
          SimpleDialogOption(
            onPressed: () { setState(() => _sortBy = 'rss'); Navigator.pop(ctx); },
            child: Text(loc.sortByMemSize),
          ),
          SimpleDialogOption(
            onPressed: () { setState(() => _sortBy = 'pid'); Navigator.pop(ctx); },
            child: Text(loc.sortByPid),
          ),
          SimpleDialogOption(
            onPressed: () { setState(() => _sortBy = 'user'); Navigator.pop(ctx); },
            child: Text(loc.sortByUser),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.processList),
        actions: [
          if (_processes.isNotEmpty)
            IconButton(
              icon: Icon(_isAutoRefresh ? Icons.pause : Icons.play_arrow),
              tooltip: _isAutoRefresh ? loc.pauseRefresh : loc.autoRefresh,
              onPressed: () {
                setState(() => _isAutoRefresh = !_isAutoRefresh);
                _startAutoRefresh();
              },
            ),
          if (_processes.isNotEmpty)
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
            icon: const Icon(Icons.sort),
            tooltip: loc.sort,
            onPressed: _showSortDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: loc.refresh,
            onPressed: _fetchProcesses,
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
                        onPressed: _fetchProcesses,
                        child: Text(loc.retry),
                      ),
                    ],
                  ),
                )
              : Column(
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
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Text(
                            '${filtered.length} / ${_processes.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const Spacer(),
                          ActionChip(
                            avatar: Icon(
                              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                              size: 16,
                            ),
                            label: Text(_sortByLabel(loc)),
                            onPressed: () => setState(() => _sortAsc = !_sortAsc),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _fetchProcesses,
                        child: filtered.isEmpty
                            ? ListView(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 80),
                                    child: Center(
                                      child: Text(
                                        loc.noProcessesFound,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.colorScheme.outline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 16),
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) => _buildProcessTile(filtered[i], theme),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _sortByLabel(AppLocalizations loc) {
    switch (_sortBy) {
      case 'cpu': return 'CPU%';
      case 'mem': return 'MEM%';
      case 'rss': return loc.memSize;
      case 'pid': return 'PID';
      case 'user': return loc.user;
      default: return 'CPU%';
    }
  }

  Widget _buildProcessTile(_ProcessInfo proc, ThemeData theme) {
    final loc = AppLocalizations.of(context);
    final cpuColor = _usageColor(proc.cpu);
    final memColor = _usageColor(proc.mem);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: proc.cpu / 100,
                  strokeWidth: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(cpuColor),
                ),
              ),
              Text(
                proc.cpu.toStringAsFixed(1),
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        title: Text(
          proc.command.length > 60 ? '${proc.command.substring(0, 60)}...' : proc.command,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            fontSize: 12,
          ),
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
            _tag(theme, _formatMem(proc.rss), theme.colorScheme.tertiary),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, color: proc.isSystem ? theme.colorScheme.error : null),
          tooltip: proc.isSystem ? loc.killSystemProcess : loc.killProcess,
          onPressed: () => _killProcess(proc),
        ),
        isThreeLine: false,
      ),
    );
  }

  Widget _tag(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: color, fontSize: 10),
      ),
    );
  }

  Color _usageColor(double percent) {
    if (percent >= 90) return Colors.red;
    if (percent >= 70) return Colors.orange;
    if (percent >= 50) return Colors.amber;
    return Colors.green;
  }
}

class _ProcessInfo {
  final String user;
  final int pid;
  final double cpu;
  final double mem;
  final int vsz;
  final int rss;
  final String stat;
  final String start;
  final String time;
  final String command;
  final bool isSystem;

  _ProcessInfo({
    required this.user,
    required this.pid,
    required this.cpu,
    required this.mem,
    required this.vsz,
    required this.rss,
    required this.stat,
    required this.start,
    required this.time,
    required this.command,
    required this.isSystem,
  });
}
