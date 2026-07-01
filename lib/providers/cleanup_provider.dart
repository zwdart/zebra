import 'package:flutter/material.dart';
import 'ssh_provider.dart';

class CleanTask {
  final String id;
  final String label;
  final String detail;
  final int sizeBytes;
  final String command;
  final bool confirmRequired;
  final int? count;

  CleanTask({
    required this.id,
    required this.label,
    required this.detail,
    required this.sizeBytes,
    required this.command,
    required this.confirmRequired,
    this.count,
  });
}

class JunkFile {
  final String path;
  final int sizeBytes;
  final String category;

  JunkFile({
    required this.path,
    required this.sizeBytes,
    required this.category,
  });
}

class CleanupProvider extends ChangeNotifier {
  late SshProvider _sshProvider;

  List<CleanTask> _tasks = [];
  List<JunkFile> _junkFiles = [];
  bool _isLoading = true;
  String? _error;
  bool _isScanningFiles = false;
  bool _isCleaning = false;
  final Set<String> _selectedFiles = {};

  CleanupProvider();

  void updateSsh(SshProvider ssh) {
    _sshProvider = ssh;
  }

  List<CleanTask> get tasks => _tasks;
  List<JunkFile> get junkFiles => _junkFiles;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isScanningFiles => _isScanningFiles;
  bool get isCleaning => _isCleaning;
  Set<String> get selectedFiles => _selectedFiles;

  int get totalSize => _tasks.fold(0, (s, t) => s + t.sizeBytes);

  bool get allSelected => _selectedFiles.length == _junkFiles.length && _junkFiles.isNotEmpty;
  bool get someSelected => _selectedFiles.isNotEmpty && _selectedFiles.length < _junkFiles.length;

  Future<void> init() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final output = await _sshProvider.sshService.execute(r"""
        echo '===APT_CACHE==='
        if command -v apt-get &>/dev/null; then
          du -sb /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo 0
        else
          echo 0
        fi
        echo '===YUM_CACHE==='
        if command -v yum &>/dev/null || command -v dnf &>/dev/null; then
          du -sb /var/cache/yum 2>/dev/null; du -sb /var/cache/dnf 2>/dev/null | tail -1 | awk '{print $1}' || echo 0
        else
          echo 0
        fi
        echo '===JOURNAL_LOGS==='
        journalctl --disk-usage 2>/dev/null | grep -oP '\d+(\.\d+)?[GMTK]' | head -1 || echo 0
        echo '===OLD_LOGS==='
        find /var/log -name '*.gz' -o -name '*.old' -o -name '*.[0-9]' 2>/dev/null | head -200 | xargs du -sb 2>/dev/null | awk '{s+=$1}END{print s+0}'
        echo '===TMP_FILES==='
        find /tmp -maxdepth 1 -mindepth 1 2>/dev/null | wc -l
        echo '===TMP_SIZE==='
        du -sb /tmp 2>/dev/null | awk '{print $1}' || echo 0
        echo '===THUMBNAILS==='
        du -sb ~/.cache/thumbnails 2>/dev/null | awk '{print $1}' || echo 0
        echo '===USER_CACHE==='
        du -sb ~/.cache 2>/dev/null | awk '{print $1}' || echo 0
        echo '===CORE_DUMPS==='
        find / -maxdepth 3 -name 'core' -o -name 'core.*' -o -name '*.core' 2>/dev/null | head -50 | xargs du -sb 2>/dev/null | awk '{s+=$1}END{print s+0}'
""");

      String extract(String key) {
        final marker = '===$key===';
        final idx = output.indexOf(marker);
        if (idx < 0) return '';
        final rest = output.substring(idx + marker.length);
        final endIdx = rest.indexOf('===');
        return (endIdx < 0 ? rest : rest.substring(0, endIdx)).trim();
      }

      final aptSize = int.tryParse(extract('APT_CACHE')) ?? 0;
      final yumSize = int.tryParse(extract('YUM_CACHE')) ?? 0;
      final journalSize = parseSize(extract('JOURNAL_LOGS'));
      final oldLogsSize = int.tryParse(extract('OLD_LOGS')) ?? 0;
      final tmpCount = int.tryParse(extract('TMP_FILES')) ?? 0;
      final tmpSize = int.tryParse(extract('TMP_SIZE')) ?? 0;
      final thumbSize = int.tryParse(extract('THUMBNAILS')) ?? 0;
      final userCacheSize = int.tryParse(extract('USER_CACHE')) ?? 0;
      final coreDumpSize = int.tryParse(extract('CORE_DUMPS')) ?? 0;

      _tasks = [
        if (aptSize > 0)
          CleanTask(id: 'apt', label: 'APT Package Cache', detail: '/var/cache/apt/archives',
              sizeBytes: aptSize, command: 'apt-get clean -y 2>/dev/null', confirmRequired: false),
        if (yumSize > 0)
          CleanTask(id: 'yum', label: 'YUM/DNF Package Cache', detail: '/var/cache/yum, /var/cache/dnf',
              sizeBytes: yumSize, command: 'yum clean all 2>/dev/null; dnf clean all 2>/dev/null', confirmRequired: false),
        if (journalSize > 0)
          CleanTask(id: 'journal', label: 'System Journal Logs', detail: 'journalctl logs older than 3 days',
              sizeBytes: journalSize, command: 'journalctl --vacuum-time=3d 2>/dev/null', confirmRequired: false),
        if (oldLogsSize > 0)
          CleanTask(id: 'oldlogs', label: 'Compressed/Old Logs', detail: '/var/log/*.gz, *.old, *.[0-9]',
              sizeBytes: oldLogsSize, command: r"find /var/log \( -name '*.gz' -o -name '*.old' -o -name '*.[0-9]' \) -delete 2>/dev/null", confirmRequired: false),
        if (thumbSize > 0)
          CleanTask(id: 'thumbs', label: 'Thumbnail Cache', detail: '~/.cache/thumbnails',
              sizeBytes: thumbSize, command: 'rm -rf ~/.cache/thumbnails/* 2>/dev/null', confirmRequired: false),
        if (userCacheSize > thumbSize && userCacheSize > 10485760)
          CleanTask(id: 'usercache', label: 'User Cache (large)', detail: '~/.cache (excluding thumbnails)',
              sizeBytes: userCacheSize, command: 'rm -rf ~/.cache/* 2>/dev/null', confirmRequired: true),
        if (coreDumpSize > 0)
          CleanTask(id: 'coredump', label: 'Core Dumps', detail: 'core files on disk',
              sizeBytes: coreDumpSize, command: r"find / -maxdepth 3 \( -name 'core' -o -name 'core.*' -o -name '*.core' \) -delete 2>/dev/null", confirmRequired: true),
        CleanTask(id: 'tmp', label: 'Temporary Files', detail: '/tmp contents',
            sizeBytes: tmpSize, command: 'find /tmp -mindepth 1 -delete 2>/dev/null', confirmRequired: false, count: tmpCount),
      ];

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> scanJunkFiles() async {
    _isScanningFiles = true;
    _junkFiles = [];
    _selectedFiles.clear();
    notifyListeners();

    try {
      final output = await _sshProvider.sshService.execute(r"""
        (echo '===TMP==='; find /tmp -maxdepth 3 -mindepth 1 -type f 2>/dev/null | head -500 | while read f; do
          size=$(stat -c%s "$f" 2>/dev/null || echo 0)
          echo "$size|$f"
        done
        echo '===LOGS==='; find /var/log -maxdepth 2 \( -name '*.gz' -o -name '*.old' -o -name '*.[0-9]' -o -name '*.log.*' \) -type f 2>/dev/null | head -200 | while read f; do
          size=$(stat -c%s "$f" 2>/dev/null || echo 0)
          echo "$size|$f"
        done
        echo '===CACHE==='; find ~/.cache -maxdepth 3 -type f -size +1M 2>/dev/null | head -200 | while read f; do
          size=$(stat -c%s "$f" 2>/dev/null || echo 0)
          echo "$size|$f"
        done
        )
""");

      final files = <JunkFile>[];
      String currentCategory = '';

      for (final line in output.split('\n')) {
        if (line.startsWith('===TMP===')) { currentCategory = 'tmp'; continue; }
        if (line.startsWith('===LOGS===')) { currentCategory = 'logs'; continue; }
        if (line.startsWith('===CACHE===')) { currentCategory = 'cache'; continue; }
        if (line.trim().isEmpty) continue;

        final sepIdx = line.indexOf('|');
        if (sepIdx < 0) continue;

        final size = int.tryParse(line.substring(0, sepIdx)) ?? 0;
        final path = line.substring(sepIdx + 1).trim();
        if (path.isEmpty || size <= 0) continue;

        files.add(JunkFile(path: path, sizeBytes: size, category: currentCategory));
      }

      files.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      _junkFiles = files;
      _isScanningFiles = false;
      notifyListeners();
    } catch (e) {
      _isScanningFiles = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> executeClean(CleanTask task) async {
    _isCleaning = true;
    notifyListeners();

    try {
      await _sshProvider.sshService.execute(task.command);
      await init();
    } finally {
      _isCleaning = false;
      notifyListeners();
    }
  }

  Future<void> cleanAll() async {
    _isCleaning = true;
    notifyListeners();

    try {
      for (final task in _tasks) {
        await _sshProvider.sshService.execute(task.command);
      }
      await init();
    } finally {
      _isCleaning = false;
      notifyListeners();
    }
  }

  Future<void> deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    _isCleaning = true;
    notifyListeners();

    try {
      final paths = _selectedFiles.map((f) => '"$f"').join(' ');
      await _sshProvider.sshService.execute('rm -f $paths 2>/dev/null');
      _selectedFiles.clear();
      notifyListeners();
      await scanJunkFiles();
    } finally {
      _isCleaning = false;
      notifyListeners();
    }
  }

  void selectFile(String path) {
    _selectedFiles.add(path);
    notifyListeners();
  }

  void deselectFile(String path) {
    _selectedFiles.remove(path);
    notifyListeners();
  }

  void selectAll() {
    _selectedFiles.addAll(_junkFiles.map((f) => f.path));
    notifyListeners();
  }

  void deselectAll() {
    _selectedFiles.clear();
    notifyListeners();
  }

  static int parseSize(String raw) {
    if (raw.isEmpty) return 0;
    raw = raw.trim();
    if (raw.endsWith('G')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1073741824).toInt();
    if (raw.endsWith('M')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1048576).toInt();
    if (raw.endsWith('K')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1024).toInt();
    if (raw.endsWith('T')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1099511627776).toInt();
    return int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  static IconData taskIcon(String id) {
    switch (id) {
      case 'apt': return Icons.inventory_2;
      case 'yum': return Icons.inventory_2;
      case 'journal': return Icons.article;
      case 'oldlogs': return Icons.description;
      case 'thumbs': return Icons.image;
      case 'usercache': return Icons.folder;
      case 'coredump': return Icons.bug_report;
      case 'tmp': return Icons.delete_sweep;
      default: return Icons.cleaning_services;
    }
  }

  static Color categoryColor(String cat) {
    switch (cat) {
      case 'tmp': return Colors.orange;
      case 'logs': return Colors.blue;
      case 'cache': return Colors.purple;
      default: return Colors.grey;
    }
  }

  static Color usageColor(double percent) {
    if (percent >= 50) return Colors.red;
    if (percent >= 25) return Colors.orange;
    return Colors.green;
  }
}
