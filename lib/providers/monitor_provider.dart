import 'dart:async';

import 'package:flutter/material.dart';
import '../services/ssh_service.dart';
import 'ssh_provider.dart';

class ServerMetrics {
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

  ServerMetrics({
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

class LoginRecord {
  final String user;
  final String terminal;
  final String from;
  final String loginTime;
  final String duration;

  LoginRecord({
    required this.user,
    required this.terminal,
    required this.from,
    required this.loginTime,
    required this.duration,
  });
}

class FailedLoginRecord {
  final String user;
  final String from;
  final String time;

  FailedLoginRecord({
    required this.user,
    required this.from,
    required this.time,
  });
}

class MonitorProvider extends ChangeNotifier {
  late SshProvider _sshProvider;
  Timer? _timer;
  int _cpuTicks1 = 0;
  int _cpuTotal1 = 0;

  ServerMetrics? _metrics;
  bool _isLoading = true;
  String? _error;
  bool _isAutoRefresh = true;
  int _refreshInterval = 3;
  List<LoginRecord> _loginHistory = [];
  List<FailedLoginRecord> _failedLogins = [];

  MonitorProvider();

  void updateSsh(SshProvider ssh) {
    _sshProvider = ssh;
  }

  ServerMetrics? get metrics => _metrics;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAutoRefresh => _isAutoRefresh;
  int get refreshInterval => _refreshInterval;
  List<LoginRecord> get loginHistory => _loginHistory;
  List<FailedLoginRecord> get failedLogins => _failedLogins;

  SshService get _ssh => _sshProvider.sshService;

  Future<void> fetchMetrics() async {
    final isFirstLoad = _metrics == null;
    _isLoading = isFirstLoad;
    _error = null;
    notifyListeners();

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

      final output = await _ssh.execute('LC_ALL=C ${cmd.toString().replaceAll('\n', '; ')}');

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

      _metrics = ServerMetrics(
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
      notifyListeners();
      startAutoRefresh();
      fetchLogins();
      fetchFailedLogins();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchLogins() async {
    try {
      final output = await _ssh.execute('last -F -n 20 2>/dev/null || last -n 20 2>/dev/null || echo ""');
      final lines = output.split('\n');
      final records = <LoginRecord>[];

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
          records.add(LoginRecord(
            user: user,
            terminal: terminal,
            from: from,
            loginTime: loginTime.trim(),
            duration: duration.trim(),
          ));
        }
      }

      _loginHistory = records;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchFailedLogins() async {
    try {
      final output = await _ssh.execute(r"""
        (
          journalctl -u sshd -u ssh --since "7 days ago" --no-pager -n 500 2>/dev/null | grep -i 'failed\|invalid\|authentication failure'
        ) || (
          grep -i 'failed password\|invalid user\|authentication failure' /var/log/auth.log /var/log/secure 2>/dev/null | tail -500
        ) || (
          lastb -F -n 100 2>/dev/null | head -100
        ) || echo ""
""");

      final lines = output.split('\n');
      final records = <FailedLoginRecord>[];

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
          final bracketMatch = RegExp(r'(\w+\s+\d+\s+[\d:]+)').firstMatch(trimmed);
          time = bracketMatch?.group(1) ?? '';
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
          records.add(FailedLoginRecord(user: user, from: from, time: time));
        }
      }

      _failedLogins = records;
      notifyListeners();
    } catch (_) {}
  }

  void startAutoRefresh() {
    _timer?.cancel();
    if (_isAutoRefresh) {
      _timer = Timer.periodic(Duration(seconds: _refreshInterval), (_) => fetchMetrics());
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

  static String formatBytes(double bytes) {
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

  static String formatUptime(double seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$d d $h h $m m';
    if (h > 0) return '$h h $m m';
    return '$m m';
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
