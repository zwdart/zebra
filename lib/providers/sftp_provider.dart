import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/sftp_file_item.dart';
import '../services/sftp_service.dart';
import '../services/compression_service.dart';
import '../services/ssh_service.dart';

class SftpProvider extends ChangeNotifier {
  final SftpService _sftpService = SftpService();
  final CompressionService _compressionService = CompressionService();
  SshService? _sshService;

  List<SftpFileItem> _files = [];
  String _currentPath = '/';
  bool _isLoading = false;
  String? _error;
  final Set<String> _selectedFiles = {};
  final List<String> _pathHistory = ['/'];

  SftpService get sftpService => _sftpService;
  CompressionService get compressionService => _compressionService;
  List<SftpFileItem> get files => List.unmodifiable(_files);
  String get currentPath => _currentPath;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Set<String> get selectedFiles => Set.unmodifiable(_selectedFiles);
  bool get isSelectionMode => _selectedFiles.isNotEmpty;
  bool get canGoBack => _pathHistory.length > 1;

  Future<void> attachToSsh(SshService sshService) async {
    _sshService = sshService;
    final client = sshService.client;
    if (client == null) throw Exception('SSH not connected');
    final sftpClient = await client.sftp();
    _sftpService.attach(sftpClient);
    _compressionService.attach(client);
  }

  Future<void> listDirectory([String? path]) async {
    final targetPath = path ?? _currentPath;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _files = await _sftpService.listDirectory(targetPath);
      _currentPath = targetPath;
      if (!_pathHistory.contains(targetPath)) {
        _pathHistory.add(targetPath);
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    _selectedFiles.clear();
    notifyListeners();
  }

  void navigateTo(String path) {
    listDirectory(path);
  }

  bool goBack() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast();
      final prevPath = _pathHistory.last;
      listDirectory(prevPath);
      return true;
    }
    return false;
  }

  void toggleSelection(String filePath) {
    if (_selectedFiles.contains(filePath)) {
      _selectedFiles.remove(filePath);
    } else {
      _selectedFiles.add(filePath);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedFiles.addAll(_files.map((f) => f.path));
    notifyListeners();
  }

  void clearSelection() {
    _selectedFiles.clear();
    notifyListeners();
  }

  Future<void> uploadFile(String localPath, String remotePath,
      {void Function(SftpProgress)? onProgress}) async {
    await _sftpService.uploadFile(localPath, remotePath, onProgress: onProgress);
    await listDirectory();
  }

  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(SftpProgress)? onProgress}) async {
    await _sftpService.downloadFile(remotePath, localPath, onProgress: onProgress);
  }

  Future<void> uploadMultipleFiles(List<String> localPaths, String remoteDir,
      {void Function(String fileName, int current, int total)? onProgress}) async {
    for (int i = 0; i < localPaths.length; i++) {
      final localPath = localPaths[i];
      final fileName = p.basename(localPath);
      final remotePath = '$remoteDir/$fileName';
      onProgress?.call(fileName, i + 1, localPaths.length);
      await _sftpService.uploadFile(localPath, remotePath);
    }
    await listDirectory();
  }

  Future<void> downloadMultipleFiles(List<String> remotePaths, String localDir,
      {void Function(String fileName, int current, int total)? onProgress}) async {
    for (int i = 0; i < remotePaths.length; i++) {
      final remotePath = remotePaths[i];
      final fileName = remotePath.split('/').last;
      final localPath = p.join(localDir, fileName);
      onProgress?.call(fileName, i + 1, remotePaths.length);
      await _sftpService.downloadFile(remotePath, localPath);
    }
  }

  Future<void> createDirectory(String name) async {
    final path = '$_currentPath/$name';
    await _sftpService.createDirectory(path);
    await listDirectory();
  }

  Future<void> deleteSelected() async {
    if (_sshService == null) throw Exception('SSH not connected');
    for (final path in _selectedFiles) {
      await _sshService!.execute('rm -rf "$path"');
    }
    _selectedFiles.clear();
    await listDirectory();
  }

  Future<void> remove(String path) async {
    if (_sshService == null) throw Exception('SSH not connected');
    await _sshService!.execute('rm -rf "$path"');
  }

  Future<void> compressSelected(String outputPath) async {
    final paths = _selectedFiles.toList();
    final progress = CompressionProgress(
      archiveName: outputPath.split('/').last,
      totalFiles: paths.length,
    );
    await _compressionService.compressTarGz(
      remoteFilePaths: paths,
      archivePath: outputPath,
      progress: progress,
    );
    await listDirectory();
  }

  void cancelAllTransfers() {
    _sftpService.cancelAllTransfers();
  }

  @override
  void dispose() {
    _sftpService.dispose();
    _compressionService.dispose();
    super.dispose();
  }
}
