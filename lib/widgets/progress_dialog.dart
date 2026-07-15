import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sftp_service.dart';
import '../services/compression_service.dart';
import '../l10n/app_localizations.dart';

class UploadProgressDialog extends StatefulWidget {
  final SftpService sftpService;
  final String fileName;
  final String localPath;
  final String remotePath;
  final VoidCallback onComplete;

  const UploadProgressDialog({
    super.key,
    required this.sftpService,
    required this.fileName,
    required this.localPath,
    required this.remotePath,
    required this.onComplete,
  });

  @override
  State<UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog> {
  SftpProgress? _progress;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    _startUpload();
  }

  void _startUpload() async {
    await widget.sftpService.uploadFile(
      widget.localPath,
      widget.remotePath,
      onProgress: (p) {
        if (mounted) {
          setState(() => _progress = p);
          if (p.completed) {
            setState(() => _isDone = true);
          }
        }
      },
    );
    if (mounted && !_progress!.cancelled) {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final progress = _progress;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_isDone ? loc.confirm : loc.uploadProgress),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.fileName, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          if (progress != null) ...[
            LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '${progress.transferredBytes} / ${progress.totalBytes} bytes (${(progress.progress * 100).toStringAsFixed(1)}%)',
              style: theme.textTheme.bodySmall,
            ),
          ] else
            const LinearProgressIndicator(),
          if (progress?.error != null) ...[
            const SizedBox(height: 8),
            Text(
              progress!.error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDone)
          TextButton(
            onPressed: () {
              widget.sftpService.cancelAllTransfers();
              Navigator.pop(context);
            },
            child: Text(loc.cancel),
          ),
        if (_isDone || progress?.error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.confirm),
          ),
      ],
    );
  }
}

class DownloadProgressDialog extends StatefulWidget {
  final SftpService sftpService;
  final String fileName;
  final String remotePath;
  final String localPath;
  final VoidCallback onComplete;

  const DownloadProgressDialog({
    super.key,
    required this.sftpService,
    required this.fileName,
    required this.remotePath,
    required this.localPath,
    required this.onComplete,
  });

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog> {
  SftpProgress? _progress;
  bool _isDone = false;
  bool _showPath = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  void _startDownload() async {
    await widget.sftpService.downloadFile(
      widget.remotePath,
      widget.localPath,
      onProgress: (p) {
        if (mounted) {
          setState(() => _progress = p);
          if (p.completed) {
            setState(() {
              _isDone = true;
              _showPath = true;
            });
          }
        }
      },
    );
    if (mounted && !_progress!.cancelled) {
      widget.onComplete();
    }
  }

  Future<void> _copyPath(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.localPath));
    if (context.mounted) {
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.pathCopied)),
      );
    }
  }

  Future<void> _openFolder() async {
    final dir = Directory(widget.localPath).parent.path;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
      }
    } catch (e) {
      debugPrint('Failed to open folder: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final progress = _progress;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(_isDone ? loc.confirm : loc.downloadProgress),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.fileName, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          if (progress != null) ...[
            LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '${progress.transferredBytes} / ${progress.totalBytes} bytes (${(progress.progress * 100).toStringAsFixed(1)}%)',
              style: theme.textTheme.bodySmall,
            ),
          ] else
            const LinearProgressIndicator(),
          if (progress?.error != null) ...[
            const SizedBox(height: 8),
            Text(
              progress!.error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (_showPath) ...[
            const SizedBox(height: 16),
            Text(
              loc.downloadPathLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              widget.localPath,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDone)
          TextButton(
            onPressed: () {
              widget.sftpService.cancelAllTransfers();
              Navigator.pop(context);
            },
            child: Text(loc.cancel),
          ),
        if (_isDone || progress?.error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.confirm),
          ),
        if (_isDone) ...[
          TextButton(
            onPressed: () => _copyPath(context),
            child: const Icon(Icons.copy, size: 18),
          ),
          TextButton(
            onPressed: () => _openFolder(),
            child: Text(loc.openFolder),
          ),
        ],
      ],
    );
  }
}

class CompressionProgressDialog extends StatefulWidget {
  final CompressionService compressionService;
  final String archiveName;
  final List<String> filePaths;
  final String outputPath;
  final VoidCallback onComplete;

  const CompressionProgressDialog({
    super.key,
    required this.compressionService,
    required this.archiveName,
    required this.filePaths,
    required this.outputPath,
    required this.onComplete,
  });

  @override
  State<CompressionProgressDialog> createState() => _CompressionProgressDialogState();
}

class _CompressionProgressDialogState extends State<CompressionProgressDialog> {
  CompressionProgress? _progress;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _startCompression();
  }

  void _startCompression() async {
    final progress = CompressionProgress(
      archiveName: widget.archiveName,
      totalFiles: widget.filePaths.length,
    );
    _progress = progress;

    _subscription = widget.compressionService.progressStream.listen((p) {
      if (mounted) {
        setState(() => _progress = p);
        if (p.completed) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) widget.onComplete();
          });
        }
      }
    });

    await widget.compressionService.compressTarGz(
      remoteFilePaths: widget.filePaths,
      archivePath: widget.outputPath,
      progress: progress,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final progress = _progress;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(progress?.completed == true
          ? loc.confirm
          : loc.compressionProgress),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.archiveName, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          if (progress != null) ...[
            LinearProgressIndicator(
              value: progress.progress > 0 ? progress.progress : null,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            if (progress.currentFile.isNotEmpty)
              Text(
                progress.currentFile,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              '${progress.processedFiles} / ${progress.totalFiles} files',
              style: theme.textTheme.bodySmall,
            ),
          ] else
            const LinearProgressIndicator(),
          if (progress?.error != null) ...[
            const SizedBox(height: 8),
            Text(
              progress!.error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (progress?.completed != true && progress?.error == null)
          TextButton(
            onPressed: () {
              widget.compressionService.cancelCompression();
              Navigator.pop(context);
            },
            child: Text(loc.cancel),
          ),
        if (progress?.completed == true || progress?.error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.confirm),
          ),
      ],
    );
  }
}
