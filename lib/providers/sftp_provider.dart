import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show debugPrint, ChangeNotifier;
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
  bool _hasLoadStarted = false;

  SftpProvider() {
    // SFTP 通道缺失/失效时,自动通过当前 SSH service 重开 channel。
    _sftpService.setOpener(_openSftpClient);
  }

  SftpService get sftpService => _sftpService;
  CompressionService get compressionService => _compressionService;
  List<SftpFileItem> get files => List.unmodifiable(_files);
  String get currentPath => _currentPath;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Set<String> get selectedFiles => Set.unmodifiable(_selectedFiles);
  bool get isSelectionMode => _selectedFiles.isNotEmpty;
  bool get canGoBack => _pathHistory.length > 1;
  bool get hasLoadStarted => _hasLoadStarted;
  bool get isAttached => _sshService != null && _sftpService.hasClient;

  Future<void> attachToSsh(SshService sshService) async {
    _sshService = sshService;
    // 注入 opener 让未 attach 时能自动开 channel;并发 attach 不会重复开连接。
    _sftpService.setOpener(_openSftpClient);
    await _sftpService.ensureClient();
    final client = sshService.client;
    if (client != null) _compressionService.attach(client);
  }

  /// 供 SftpService 在需要(未 attach / channel 失效)时自动重建 SFTP channel。
  Future<SftpClient> _openSftpClient() async {
    final sshService = _sshService;
    if (sshService == null) {
      throw Exception('SSH service not attached to SFTP provider');
    }
    return sshService.sftp();
  }

  /// 立即进入 loading 状态(不实际发起请求),用于让界面在 attach 阶段就显示转圈
  void markLoading() {
    _isLoading = true;
    _hasLoadStarted = true;
    _error = null;
    notifyListeners();
  }

  /// 记录 attach 失败等错误并退出 loading(配合 markLoading 使用)
  void reportError(String message) {
    _error = message;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> refreshDirectory([String? path]) async {
    final targetPath = path ?? _currentPath;
    _isLoading = true;
    _hasLoadStarted = true;
    _error = null;
    notifyListeners();

    bool succeeded = false;
    try {
      final items = await _listDirectoryOnce(targetPath);
      _files = items;
      _currentPath = targetPath;
      _selectedFiles.clear();
      succeeded = true;
      debugPrint('[SFTP] refreshDirectory($targetPath) 成功, ${items.length} 项');
    } catch (e) {
      _error = e.toString();
      debugPrint('[SFTP] refreshDirectory($targetPath) 失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return succeeded;
  }

  Future<void> listDirectory([String? path]) async {
    final succeeded = await refreshDirectory(path);
    if (succeeded && path != null && !_pathHistory.contains(path)) {
      _pathHistory.add(path);
    }
  }

  Future<List<SftpFileItem>> _listDirectoryOnce(String targetPath) async {
    return _sftpService.listDirectory(targetPath);
  }

  void navigateTo(String path) {
    listDirectory(path);
  }

  bool goBack() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast();
      final prevPath = _pathHistory.last;
      // 回退走 refresh, 不把旧路径再次 push 进 history, 否则 canGoBack 会因去重失败而恒为 true
      refreshDirectory(prevPath);
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

  Future<void> remove(String path) async {
    if (_sshService == null) throw Exception('SSH not connected');
    await _sshService!.execute('rm -rf "$path"');
  }

  Future<void> deleteSelected() async {
    if (_sshService == null) throw Exception('SSH not connected');
    for (final path in _selectedFiles) {
      await _sshService!.execute('rm -rf "$path"');
    }
    _selectedFiles.clear();
    await listDirectory();
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
    // Close the SFTP channel so the SSH connection's channel count stays bounded
    final sftpClient = _sftpService.currentClient;
    _sftpService.dispose();
    if (sftpClient != null && _sshService != null) {
      _sshService!.closeSftp(sftpClient);
    }
    _compressionService.dispose();
    super.dispose();
  }
}
