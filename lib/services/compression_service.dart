import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

class CompressionProgress {
  final String archiveName;
  final int totalFiles;
  int processedFiles;
  bool cancelled;
  bool completed;
  String? error;
  String currentFile;

  CompressionProgress({
    required this.archiveName,
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.cancelled = false,
    this.completed = false,
    this.error,
    this.currentFile = '',
  });

  double get progress =>
      totalFiles > 0 ? processedFiles / totalFiles : 0;
  bool get isRunning => !cancelled && !completed;
}

class CompressionService {
  SSHClient? _client;
  SSHSession? _currentSession;

  final StreamController<CompressionProgress> _progressController =
      StreamController<CompressionProgress>.broadcast();

  Stream<CompressionProgress> get progressStream => _progressController.stream;

  void attach(SSHClient client) {
    _client = client;
  }

  Future<void> compressFiles({
    required List<String> remoteFilePaths,
    required String outputPath,
    required CompressionProgress progress,
    void Function(CompressionProgress)? onProgress,
  }) async {
    if (_client == null) throw Exception('SSH client not connected');

    try {
      final escapedPaths = remoteFilePaths.map((p) => '"$p"').join(' ');
      final command = 'tar czf "$outputPath" -C / $escapedPaths 2>/dev/null || '
          'zip -r "$outputPath" $escapedPaths 2>/dev/null';

      _currentSession = await _client!.execute(command);

      _currentSession!.stdout.listen((data) {});

      _currentSession!.stderr.listen((data) {
        final text = String.fromCharCodes(data);
        if (text.contains('adding:')) {
          progress.processedFiles++;
          final match = RegExp(r'adding:\s*(.+)').firstMatch(text);
          if (match != null) {
            progress.currentFile = match.group(1) ?? '';
          }
          onProgress?.call(progress);
          _progressController.add(progress);
        }
      });

      await _currentSession!.done;
      progress.completed = true;
      onProgress?.call(progress);
      _progressController.add(progress);
    } catch (e) {
      if (!progress.cancelled) {
        progress.error = e.toString();
      }
      onProgress?.call(progress);
      _progressController.add(progress);
    }
  }

  Future<void> compressTarGz({
    required List<String> remoteFilePaths,
    required String archivePath,
    required CompressionProgress progress,
    void Function(CompressionProgress)? onProgress,
  }) async {
    if (_client == null) throw Exception('SSH client not connected');

    try {
      final escapedPaths = remoteFilePaths.map((p) => '"$p"').join(' ');
      final command = 'tar czf "$archivePath" $escapedPaths 2>&1';

      _currentSession = await _client!.execute(command);

      _currentSession!.stdout.listen((data) {
        final text = String.fromCharCodes(data);
        final lines = text.split('\n').where((l) => l.isNotEmpty);
        for (final line in lines) {
          if (progress.cancelled) {
            _currentSession?.close();
            break;
          }
          progress.processedFiles++;
          progress.currentFile = line.trim();
          onProgress?.call(progress);
          _progressController.add(progress);
        }
      });

      await _currentSession!.done;
      progress.completed = true;
      onProgress?.call(progress);
      _progressController.add(progress);
    } catch (e) {
      if (!progress.cancelled) {
        progress.error = e.toString();
      }
      onProgress?.call(progress);
      _progressController.add(progress);
    }
  }

  void cancelCompression() {
    _currentSession?.close();
    _currentSession = null;
  }

  void dispose() {
    cancelCompression();
    _progressController.close();
  }
}
