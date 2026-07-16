import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../services/sftp_service.dart';

class BatchUploadItem {
  final String localPath;
  final String remotePath;
  final bool isDirectory;
  final int size;

  BatchUploadItem({
    required this.localPath,
    required this.remotePath,
    this.isDirectory = false,
    this.size = 0,
  });
}

enum BatchUploadStatus { pending, uploading, completed, failed, skipped }

enum UploadPhase { creatingDirectories, uploadingFiles, completed }

class _FileUploadInfo {
  final BatchUploadItem item;
  final int size;
  BatchUploadStatus status;
  String? errorMessage;

  _FileUploadInfo({
    required this.item,
    required this.size,
    required this.status,
  });
}

class BatchUploadProgressDialog extends StatefulWidget {
  final SftpService sftpService;
  final List<BatchUploadItem> items;
  final VoidCallback onComplete;

  const BatchUploadProgressDialog({
    super.key,
    required this.sftpService,
    required this.items,
    required this.onComplete,
  });

  @override
  State<BatchUploadProgressDialog> createState() => _BatchUploadProgressDialogState();
}

class _BatchUploadProgressDialogState extends State<BatchUploadProgressDialog> {
  int _currentIndex = 0;
  int _completedCount = 0;
  int _failedCount = 0;
  double _currentFileProgress = 0;
  bool _isDone = false;
  bool _cancelled = false;
  UploadPhase _currentPhase = UploadPhase.creatingDirectories;
  int _directoriesCreated = 0;
  final List<String> _failedFiles = [];
  final List<_FileUploadInfo> _fileInfos = [];

  // Speed tracking
  int _totalBytesTransferred = 0;
  DateTime? _startTime;
  DateTime? _lastSpeedUpdate;
  int _lastBytesAtSpeedUpdate = 0;
  double _currentSpeed = 0; // bytes per second

  @override
  void initState() {
    super.initState();
    _initFileInfos();
    _startUpload();
  }

  void _initFileInfos() {
    for (final item in widget.items) {
      if (!item.isDirectory) {
        final file = File(item.localPath);
        final exists = file.existsSync();
        final size = exists ? file.lengthSync() : 0;
        _fileInfos.add(_FileUploadInfo(
          item: item,
          size: size,
          status: BatchUploadStatus.pending,
        ));
      }
    }
  }

  int get _totalFiles => widget.items.where((i) => !i.isDirectory).length;

  int get _totalBytes {
    int total = 0;
    for (final item in widget.items) {
      if (!item.isDirectory) {
        final file = File(item.localPath);
        if (file.existsSync()) {
          total += file.lengthSync();
        }
      }
    }
    return total;
  }

  double get _overallProgress {
    if (_totalBytes == 0) return 1.0;
    return _totalBytesTransferred / _totalBytes;
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  void _updateSpeed(int transferredBytes) {
    final now = DateTime.now();
    _totalBytesTransferred = transferredBytes;

    if (_startTime == null) {
      _startTime = now;
      _lastSpeedUpdate = now;
      _lastBytesAtSpeedUpdate = transferredBytes;
      return;
    }

    final timeSinceLastUpdate = now.difference(_lastSpeedUpdate!).inMilliseconds;
    if (timeSinceLastUpdate > 500) { // Update speed every 500ms
      final bytesSinceLastUpdate = transferredBytes - _lastBytesAtSpeedUpdate;
      _currentSpeed = bytesSinceLastUpdate * 1000 / timeSinceLastUpdate;
      _lastSpeedUpdate = now;
      _lastBytesAtSpeedUpdate = transferredBytes;
    }
  }

  Duration? get _estimatedTimeRemaining {
    if (_currentSpeed <= 0 || _totalBytes == 0) return null;
    final remaining = _totalBytes - _totalBytesTransferred;
    return Duration(milliseconds: (remaining / _currentSpeed * 1000).round());
  }

  int get _totalDirectories => widget.items.where((i) => i.isDirectory).length;

  Future<void> _startUpload() async {
    // Phase 1: Create remote directories first
    final directories = widget.items.where((i) => i.isDirectory).toList();
    if (directories.isNotEmpty && mounted) {
      setState(() {
        _currentPhase = UploadPhase.creatingDirectories;
      });
    }

    for (int i = 0; i < directories.length; i++) {
      if (_cancelled) break;
      final dir = directories[i];
      setState(() {
        _directoriesCreated = i;
      });
      try {
        await _createRemoteDirectoryRecursive(dir.remotePath);
      } catch (e) {
        // Directory creation failed, continue with file uploads
      }
      setState(() {
        _directoriesCreated = i + 1;
      });
    }

    // Phase 2: Upload files
    final files = widget.items.where((i) => !i.isDirectory).toList();
    if (files.isNotEmpty && mounted) {
      setState(() {
        _currentPhase = UploadPhase.uploadingFiles;
      });
    }

    int cumulativeBytes = 0;

    for (int i = 0; i < files.length; i++) {
      if (_cancelled) break;

      final item = files[i];
      final fileInfoIndex = _fileInfos.indexWhere((f) => f.item == item);
      final fileInfo = fileInfoIndex >= 0 ? _fileInfos[fileInfoIndex] : null;

      final file = File(item.localPath);
      if (!file.existsSync()) {
        if (fileInfo != null) {
          fileInfo.status = BatchUploadStatus.failed;
        }
        _failedFiles.add(p.basename(item.localPath));
        _failedCount++;
        continue;
      }

      setState(() {
        _currentIndex = i;
        _currentFileProgress = 0;
        if (fileInfo != null) {
          fileInfo.status = BatchUploadStatus.uploading;
        }
      });

      try {
        final fileBytes = file.lengthSync();
        await widget.sftpService.uploadFile(
          item.localPath,
          item.remotePath,
          onProgress: (progress) {
            if (mounted && !_cancelled) {
              setState(() {
                _currentFileProgress = progress.progress;
                _updateSpeed(cumulativeBytes + progress.transferredBytes);
              });
            }
          },
        );
        cumulativeBytes += fileBytes;
        _completedCount++;
        if (fileInfo != null) {
          fileInfo.status = BatchUploadStatus.completed;
        }
      } catch (e) {
        _failedCount++;
        _failedFiles.add(p.basename(item.localPath));
        if (fileInfo != null) {
          fileInfo.status = BatchUploadStatus.failed;
          fileInfo.errorMessage = e.toString();
        }
      }
    }

    if (mounted) {
      setState(() {
        _isDone = true;
        _currentPhase = UploadPhase.completed;
        _currentFileProgress = 1.0;
      });
    }
  }

  Future<void> _createRemoteDirectoryRecursive(String remotePath) async {
    final parts = remotePath.split('/').where((p) => p.isNotEmpty).toList();
    String current = '';
    for (final part in parts) {
      current = '$current/$part';
      try {
        await widget.sftpService.createDirectory(current);
      } catch (_) {
        // Directory might already exist, continue
      }
    }
  }

  void _cancel() {
    _cancelled = true;
    widget.sftpService.cancelAllTransfers();
    Navigator.pop(context);
  }

  void _close() {
    Navigator.pop(context);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isDone
                ? (_failedCount > 0 ? Icons.warning : Icons.check_circle)
                : Icons.cloud_upload,
            color: _isDone
                ? (_failedCount > 0 ? Colors.orange : Colors.green)
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isDone
                  ? (_failedCount > 0 ? loc.uploadFailed : loc.uploadCompleted)
                  : loc.batchUpload,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall progress
            if (!_isDone) ...[
              _buildProgressInfo(loc, theme),
              const SizedBox(height: 12),
              _buildSpeedInfo(loc, theme),
            ],

            if (_isDone) ...[
              const SizedBox(height: 8),
              _buildSummary(loc, theme),
            ],

            const SizedBox(height: 16),

            // Current phase progress
            if (!_isDone) ...[
              _buildPhaseProgress(loc, theme),
            ],

            // Current file progress (only when uploading files)
            if (!_isDone && _currentPhase == UploadPhase.uploadingFiles && _currentIndex < widget.items.length) ...[
              _buildCurrentFileProgress(loc, theme),
            ],

            // File list (show last few files)
            if (_fileInfos.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildFileList(loc, theme),
            ],

            // Failed files list
            if (_isDone && _failedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildFailedFilesList(loc, theme),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDone)
          TextButton(
            onPressed: _cancel,
            child: Text(loc.cancel),
          ),
        if (_isDone)
          TextButton(
            onPressed: _close,
            child: Text(loc.confirm),
          ),
      ],
    );
  }

  Widget _buildProgressInfo(AppLocalizations loc, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total progress bar
        Row(
          children: [
            Text(loc.totalProgress, style: theme.textTheme.bodySmall),
            const Spacer(),
            Text(
              '$_completedCount / $_totalFiles',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: _overallProgress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildSpeedInfo(AppLocalizations loc, ThemeData theme) {
    final eta = _estimatedTimeRemaining;
    return Row(
      children: [
        if (_currentSpeed > 0 && _currentPhase == UploadPhase.uploadingFiles) ...[
          Icon(Icons.speed, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            _formatSpeed(_currentSpeed),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
        if (_currentSpeed > 0 && eta != null && _currentPhase == UploadPhase.uploadingFiles) ...[
          const SizedBox(width: 16),
          Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            _formatDuration(eta),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }

  Widget _buildPhaseProgress(AppLocalizations loc, ThemeData theme) {
    if (_currentPhase == UploadPhase.creatingDirectories && _totalDirectories > 0) {
      // Directory creation phase
      final progress = _totalDirectories > 0 ? _directoriesCreated / _totalDirectories : 0.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                loc.creatingFolders,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              ),
              const Spacer(),
              Text(
                '$_directoriesCreated / $_totalDirectories',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      );
    } else if (_currentPhase == UploadPhase.uploadingFiles) {
      // File upload phase
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_upload, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                loc.uploading,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCurrentFileProgress(AppLocalizations loc, ThemeData theme) {
    final item = widget.items[_currentIndex];
    final fileName = p.basename(item.localPath);
    final fileInfo = _fileInfos.firstWhere(
      (f) => f.item == item,
      orElse: () => _FileUploadInfo(item: item, size: 0, status: BatchUploadStatus.uploading),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.insert_drive_file, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fileName,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatSize(fileInfo.size),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _currentFileProgress > 0 ? _currentFileProgress : null,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 4),
        Text(
          '${(_currentFileProgress * 100).toStringAsFixed(1)}%',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildFileList(AppLocalizations loc, ThemeData theme) {
    // Show the current file and next few pending files
    final displayCount = 5;
    final startIndex = _currentIndex.clamp(0, (_fileInfos.length - displayCount).clamp(0, _fileInfos.length));
    final endIndex = (startIndex + displayCount).clamp(0, _fileInfos.length);
    final displayFiles = _fileInfos.sublist(startIndex, endIndex);

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Text(loc.fileProgress, style: theme.textTheme.bodySmall),
                const Spacer(),
                Text('${_completedCount + _failedCount} / $_totalFiles',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // File list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: displayFiles.length,
              itemBuilder: (ctx, i) {
                final info = displayFiles[i];
                final fileName = p.basename(info.item.localPath);
                return _buildFileListTile(info, fileName, theme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileListTile(_FileUploadInfo info, String fileName, ThemeData theme) {
    IconData icon;
    Color iconColor;
    String statusText;

    switch (info.status) {
      case BatchUploadStatus.completed:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        statusText = _formatSize(info.size);
        break;
      case BatchUploadStatus.uploading:
        icon = Icons.cloud_upload;
        iconColor = theme.colorScheme.primary;
        statusText = '${(_currentFileProgress * 100).toStringAsFixed(0)}%';
        break;
      case BatchUploadStatus.failed:
        icon = Icons.error;
        iconColor = Colors.red;
        statusText = 'Failed';
        break;
      case BatchUploadStatus.pending:
        icon = Icons.hourglass_empty;
        iconColor = theme.colorScheme.outline;
        statusText = _formatSize(info.size);
        break;
      case BatchUploadStatus.skipped:
        icon = Icons.skip_next;
        iconColor = Colors.grey;
        statusText = 'Skipped';
        break;
    }

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 16, color: iconColor),
      title: Text(
        fileName,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      subtitle: (info.status == BatchUploadStatus.failed && info.errorMessage != null)
          ? Text(
              info.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error, fontSize: 11),
            )
          : null,
      trailing: Text(
        statusText,
        style: theme.textTheme.bodySmall?.copyWith(color: iconColor),
      ),
    );
  }

  Widget _buildSummary(AppLocalizations loc, ThemeData theme) {
    final directoryCount = widget.items.where((i) => i.isDirectory).length;
    final totalSize = _totalBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              '$_completedCount ${loc.uploadCompleted}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
            ),
            if (totalSize > 0) ...[
              const SizedBox(width: 8),
              Text(
                '(${_formatSize(totalSize)})',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
        if (_failedCount > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.error, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                '$_failedCount ${loc.uploadFailed}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
              ),
            ],
          ),
        ],
        if (directoryCount > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.folder, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                '$directoryCount ${loc.newFolder}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFailedFilesList(AppLocalizations loc, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${loc.uploadFailed} (${_failedFiles.length}):',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 100),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _failedFiles.length,
            itemBuilder: (ctx, i) {
              final failedName = _failedFiles[i];
              final failedInfo = _fileInfos.firstWhere(
                (f) => f.status == BatchUploadStatus.failed && p.basename(f.item.localPath) == failedName,
                orElse: () => _FileUploadInfo(item: BatchUploadItem(localPath: '', remotePath: ''), size: 0, status: BatchUploadStatus.failed),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 12, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            failedName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (failedInfo.errorMessage != null)
                            Text(
                              failedInfo.errorMessage!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
