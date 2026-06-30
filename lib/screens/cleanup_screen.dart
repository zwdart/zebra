import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ssh_provider.dart';
import '../l10n/app_localizations.dart';

class CleanupScreen extends StatefulWidget {
  const CleanupScreen({super.key});

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends State<CleanupScreen> {
  bool _isLoading = true;
  String? _error;
  List<_CleanTask> _tasks = [];
  List<_JunkFile> _junkFiles = [];
  bool _scanningFiles = false;
  bool _cleaning = false;
  final Set<String> _selectedFiles = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<String> _exec(String cmd) async {
    final sshProvider = context.read<SshProvider>();
    return sshProvider.sshService.execute(cmd);
  }

  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final output = await _exec(r"""
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
        echo '===SWAP==='
        swapon --show 2>/dev/null | awk 'NR>1{print $1}' || echo ''
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
      final journalRaw = extract('JOURNAL_LOGS');
      final journalSize = _parseSize(journalRaw);
      final oldLogsSize = int.tryParse(extract('OLD_LOGS')) ?? 0;
      final tmpCount = int.tryParse(extract('TMP_FILES')) ?? 0;
      final tmpSize = int.tryParse(extract('TMP_SIZE')) ?? 0;
      final thumbSize = int.tryParse(extract('THUMBNAILS')) ?? 0;
      final userCacheSize = int.tryParse(extract('USER_CACHE')) ?? 0;
      final coreDumpSize = int.tryParse(extract('CORE_DUMPS')) ?? 0;

      _tasks = [
        if (aptSize > 0)
          _CleanTask(
            id: 'apt',
            label: 'APT Package Cache',
            detail: '/var/cache/apt/archives',
            sizeBytes: aptSize,
            command: 'apt-get clean -y 2>/dev/null',
            confirmRequired: false,
          ),
        if (yumSize > 0)
          _CleanTask(
            id: 'yum',
            label: 'YUM/DNF Package Cache',
            detail: '/var/cache/yum, /var/cache/dnf',
            sizeBytes: yumSize,
            command: 'yum clean all 2>/dev/null; dnf clean all 2>/dev/null',
            confirmRequired: false,
          ),
        if (journalSize > 0)
          _CleanTask(
            id: 'journal',
            label: 'System Journal Logs',
            detail: 'journalctl logs older than 3 days',
            sizeBytes: journalSize,
            command: 'journalctl --vacuum-time=3d 2>/dev/null',
            confirmRequired: false,
          ),
        if (oldLogsSize > 0)
          _CleanTask(
            id: 'oldlogs',
            label: 'Compressed/Old Logs',
            detail: '/var/log/*.gz, *.old, *.[0-9]',
            sizeBytes: oldLogsSize,
            command: r"find /var/log \( -name '*.gz' -o -name '*.old' -o -name '*.[0-9]' \) -delete 2>/dev/null",
            confirmRequired: false,
          ),
        if (thumbSize > 0)
          _CleanTask(
            id: 'thumbs',
            label: 'Thumbnail Cache',
            detail: '~/.cache/thumbnails',
            sizeBytes: thumbSize,
            command: 'rm -rf ~/.cache/thumbnails/* 2>/dev/null',
            confirmRequired: false,
          ),
        if (userCacheSize > thumbSize && userCacheSize > 10485760)
          _CleanTask(
            id: 'usercache',
            label: 'User Cache (large)',
            detail: '~/.cache (excluding thumbnails)',
            sizeBytes: userCacheSize,
            command: 'rm -rf ~/.cache/* 2>/dev/null',
            confirmRequired: true,
          ),
        if (coreDumpSize > 0)
          _CleanTask(
            id: 'coredump',
            label: 'Core Dumps',
            detail: 'core files on disk',
            sizeBytes: coreDumpSize,
            command: r"find / -maxdepth 3 \( -name 'core' -o -name 'core.*' -o -name '*.core' \) -delete 2>/dev/null",
            confirmRequired: true,
          ),
        _CleanTask(
          id: 'tmp',
          label: 'Temporary Files',
          detail: '/tmp contents',
          sizeBytes: tmpSize,
          command: 'find /tmp -mindepth 1 -delete 2>/dev/null',
          confirmRequired: false,
          count: tmpCount,
        ),
      ];

      if (mounted) {
        setState(() {
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

  int _parseSize(String raw) {
    if (raw.isEmpty) return 0;
    raw = raw.trim();
    if (raw.endsWith('G')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1073741824).toInt();
    if (raw.endsWith('M')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1048576).toInt();
    if (raw.endsWith('K')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1024).toInt();
    if (raw.endsWith('T')) return ((double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) * 1099511627776).toInt();
    return int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  String _formatBytes(int bytes) {
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

  int get _totalSize => _tasks.fold(0, (s, t) => s + t.sizeBytes);

  Future<void> _scanJunkFiles() async {
    setState(() {
      _scanningFiles = true;
      _junkFiles = [];
      _selectedFiles.clear();
    });

    try {
      final output = await _exec(r"""
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

      final files = <_JunkFile>[];
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

        files.add(_JunkFile(
          path: path,
          sizeBytes: size,
          category: currentCategory,
        ));
      }

      files.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

      if (mounted) {
        setState(() {
          _junkFiles = files;
          _scanningFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanningFiles = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _executeClean(_CleanTask task) async {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

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

    setState(() => _cleaning = true);

    try {
      await _exec(task.command);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.cleanCompleted(task.label))),
        );
      }
      await _init();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.cleanFailed}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _cleanAll() async {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_sweep, color: theme.colorScheme.primary, size: 48),
        title: Text(loc.cleanAll),
        content: Text(loc.cleanAllMsgParam(_formatBytes(_totalSize))),
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

    setState(() => _cleaning = true);

    try {
      for (final task in _tasks) {
        await _exec(task.command);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.cleanCompleted(loc.quickClean))),
        );
      }
      await _init();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.cleanFailed}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _deleteSelectedFiles() async {
    final loc = AppLocalizations.of(context);

    if (_selectedFiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.confirmDeleteSelected),
        content: Text(loc.confirmDeleteSelectedMsg(_selectedFiles.length)),
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

    setState(() => _cleaning = true);

    try {
      final paths = _selectedFiles.map((f) => '"$f"').join(' ');
      await _exec('rm -f $paths 2>/dev/null');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.deletedFiles(_selectedFiles.length))),
        );
        setState(() {
          _selectedFiles.clear();
          _junkFiles.removeWhere((f) => _selectedFiles.contains(f.path));
        });
      }
      await _scanJunkFiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.deleteFailed}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.diskCleanup),
        actions: [
          if (!_isLoading && _tasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: loc.cleanAll,
              onPressed: _cleaning ? null : _cleanAll,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: loc.refresh,
            onPressed: _init,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _init, child: Text(loc.retry)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSummaryCard(theme, loc),
                    const SizedBox(height: 16),
                    _buildSectionTitle(theme, Icons.cleaning_services, loc.quickClean),
                    const SizedBox(height: 8),
                    ..._tasks.map((t) => _buildTaskCard(t, theme, loc)),
                    const SizedBox(height: 16),
                    _buildSectionTitle(theme, Icons.folder_open, loc.tempFileBrowser),
                    const SizedBox(height: 8),
                    _buildFileBrowser(theme, loc),
                  ],
                ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, AppLocalizations loc) {
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
                  Text(loc.totalCleanable, style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  )),
                  const SizedBox(height: 4),
                  Text(
                    _formatBytes(_totalSize),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
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

  Widget _buildTaskCard(_CleanTask task, ThemeData theme, AppLocalizations loc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _usageColor(task.sizeBytes / _totalSize * 100).withValues(alpha: 0.15),
          child: Icon(
            _taskIcon(task.id),
            color: _usageColor(task.sizeBytes / _totalSize * 100),
            size: 20,
          ),
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
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatBytes(task.sizeBytes),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: _cleaning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cleaning_services, size: 20),
              tooltip: loc.clean,
              onPressed: _cleaning ? null : () => _executeClean(task),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileBrowser(ThemeData theme, AppLocalizations loc) {
    return Column(
      children: [
        if (!_scanningFiles && _junkFiles.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.search),
              title: Text(loc.scanTempFiles),
              subtitle: Text(loc.scanTempFilesDesc),
              trailing: ElevatedButton(
                onPressed: _scanJunkFiles,
                child: Text(loc.scan),
              ),
            ),
          ),
        if (_scanningFiles)
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
        if (!_scanningFiles && _junkFiles.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: _selectedFiles.length == _junkFiles.length,
                    tristate: _selectedFiles.isNotEmpty && _selectedFiles.length < _junkFiles.length,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedFiles.addAll(_junkFiles.map((f) => f.path));
                        } else {
                          _selectedFiles.clear();
                        }
                      });
                    },
                  ),
                  Text(loc.selectAll),
                  const Spacer(),
                  Text(
                    '${_selectedFiles.length}/${_junkFiles.length}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  if (_selectedFiles.isNotEmpty)
                    FilledButton.icon(
                      onPressed: _cleaning ? null : _deleteSelectedFiles,
                      icon: const Icon(Icons.delete, size: 16),
                      label: Text(loc.delete),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: loc.rescan,
                    onPressed: _scanJunkFiles,
                  ),
                ],
              ),
            ),
          ),
          ..._junkFiles.map((f) => _buildFileTile(f, theme, loc)),
        ],
      ],
    );
  }

  Widget _buildFileTile(_JunkFile file, ThemeData theme, AppLocalizations loc) {
    final isSelected = _selectedFiles.contains(file.path);
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (v) {
          setState(() {
            if (v == true) {
              _selectedFiles.add(file.path);
            } else {
              _selectedFiles.remove(file.path);
            }
          });
        },
        title: Text(
          file.path.split('/').last,
          style: const TextStyle(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          file.path,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            fontFamily: 'monospace',
            fontSize: 10,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        secondary: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _categoryColor(file.category).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _formatBytes(file.sizeBytes),
            style: theme.textTheme.labelSmall?.copyWith(
              color: _categoryColor(file.category),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  IconData _taskIcon(String id) {
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

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'tmp': return Colors.orange;
      case 'logs': return Colors.blue;
      case 'cache': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _usageColor(double percent) {
    if (percent >= 50) return Colors.red;
    if (percent >= 25) return Colors.orange;
    return Colors.green;
  }
}

class _CleanTask {
  final String id;
  final String label;
  final String detail;
  final int sizeBytes;
  final String command;
  final bool confirmRequired;
  final int? count;

  _CleanTask({
    required this.id,
    required this.label,
    required this.detail,
    required this.sizeBytes,
    required this.command,
    required this.confirmRequired,
    this.count,
  });
}

class _JunkFile {
  final String path;
  final int sizeBytes;
  final String category;

  _JunkFile({
    required this.path,
    required this.sizeBytes,
    required this.category,
  });
}
