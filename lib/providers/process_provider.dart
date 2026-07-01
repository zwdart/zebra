import 'dart:async';

import 'package:flutter/material.dart';
import 'ssh_provider.dart';

class ProcessInfo {
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

  ProcessInfo({
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

class ProcessProvider extends ChangeNotifier {
  late SshProvider _sshProvider;
  Timer? _timer;

  List<ProcessInfo> _processes = [];
  bool _isLoading = true;
  String? _error;
  bool _isAutoRefresh = true;
  int _refreshInterval = 5;
  String _sortBy = 'cpu';
  bool _sortAsc = false;
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

  ProcessProvider();

  void updateSsh(SshProvider ssh) {
    _sshProvider = ssh;
  }

  List<ProcessInfo> get processes => _processes;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAutoRefresh => _isAutoRefresh;
  int get refreshInterval => _refreshInterval;
  String get sortBy => _sortBy;
  bool get sortAsc => _sortAsc;
  String get searchQuery => _searchQuery;

  List<ProcessInfo> get filteredProcesses {
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
        case 'pid': cmp = a.pid.compareTo(b.pid);
        case 'user': cmp = a.user.compareTo(b.user);
        case 'cpu': cmp = a.cpu.compareTo(b.cpu);
        case 'mem': cmp = a.mem.compareTo(b.mem);
        case 'rss': cmp = a.rss.compareTo(b.rss);
        default: cmp = a.cpu.compareTo(b.cpu);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  bool _isSystemProcess(String user, String command) {
    if (_systemUsers.contains(user)) return true;
    final exe = command.split(' ').first;
    for (final prefix in _systemBinaries) {
      if (exe.startsWith(prefix)) return true;
    }
    return false;
  }

  Future<void> fetchProcesses() async {
    final isFirstLoad = _processes.isEmpty;
    _isLoading = isFirstLoad;
    _error = null;
    notifyListeners();

    try {
      final output = await _sshProvider.sshService.execute(
        r"ps aux --sort=-pcpu 2>/dev/null || ps aux 2>/dev/null || echo 'ERROR'",
      );

      if (output.trim() == 'ERROR' || output.trim().isEmpty) {
        _error = 'Failed to list processes';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final lines = output.split('\n');
      final procs = <ProcessInfo>[];

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 11) continue;

        final pid = int.tryParse(parts[1]);
        if (pid == null) continue;

        procs.add(ProcessInfo(
          user: parts[0],
          pid: pid,
          cpu: double.tryParse(parts[2]) ?? 0,
          mem: double.tryParse(parts[3]) ?? 0,
          vsz: int.tryParse(parts[4]) ?? 0,
          rss: int.tryParse(parts[5]) ?? 0,
          stat: parts[7],
          start: parts[8],
          time: parts[9],
          command: parts.sublist(10).join(' '),
          isSystem: _isSystemProcess(parts[0], parts.sublist(10).join(' ')),
        ));
      }

      _processes = procs;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> killProcess(ProcessInfo proc) async {
    await _sshProvider.sshService.execute('kill -15 ${proc.pid} 2>/dev/null');
    await Future.delayed(const Duration(milliseconds: 500));
    await fetchProcesses();
  }

  void startAutoRefresh() {
    _timer?.cancel();
    if (_isAutoRefresh) {
      _timer = Timer.periodic(Duration(seconds: _refreshInterval), (_) => fetchProcesses());
    }
  }

  void stopAutoRefresh() {
    _timer?.cancel();
    _timer = null;
  }

  void setAutoRefresh(bool value) {
    _isAutoRefresh = value;
    if (_isAutoRefresh) {
      startAutoRefresh();
    } else {
      stopAutoRefresh();
    }
    notifyListeners();
  }

  void setRefreshInterval(int seconds) {
    _refreshInterval = seconds;
    if (_isAutoRefresh) startAutoRefresh();
    notifyListeners();
  }

  void setSortBy(String field) {
    _sortBy = field;
    notifyListeners();
  }

  void toggleSortOrder() {
    _sortAsc = !_sortAsc;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  static String formatMem(int kb) {
    if (kb >= 1048576) return '${(kb / 1048576).toStringAsFixed(1)} G';
    if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(1)} M';
    return '$kb K';
  }

  static Color usageColor(double percent) {
    if (percent >= 90) return Colors.red;
    if (percent >= 70) return Colors.orange;
    if (percent >= 50) return Colors.amber;
    return Colors.green;
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
