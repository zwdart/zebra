import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import '../models/sftp_file_item.dart';

class SftpProgress {
  final String fileName;
  final int totalBytes;
  int transferredBytes;
  bool cancelled;
  bool completed;
  String? error;

  SftpProgress({
    required this.fileName,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.cancelled = false,
    this.completed = false,
    this.error,
  });

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0;
  bool get isRunning => !cancelled && !completed;
}

class SftpService {
  SftpClient? _sftpClient;
  Future<SftpClient>? _pendingAttach;
  /// provider 注入的「未 attach 时如何开 SFTP channel」回调
  /// (通常是 `() => sshService.sftp`)。
  Future<SftpClient> Function()? _openClient;
  final Map<String, SftpProgress> _activeTransfers = {};
  final StreamController<Map<String, SftpProgress>> _progressController =
      StreamController<Map<String, SftpProgress>>.broadcast();

  Stream<Map<String, SftpProgress>> get progressStream => _progressController.stream;
  Map<String, SftpProgress> get activeTransfers => Map.unmodifiable(_activeTransfers);
  bool get hasClient => _sftpClient != null;
  /// The currently attached SFTP client (null before attach or after detach).
  SftpClient? get currentClient => _sftpClient;

  /// 注入 attach 回调:client 缺失时各 SFTP 操作会自动调它重开通道。
  void setOpener(Future<SftpClient> Function() openClient, {dynamic ownerSshService}) {
    _openClient = openClient;
  }

  void attach(SftpClient client) {
    _sftpClient = client;
  }

  /// 幂等地确保 SFTP channel 可用:已有 client 直接复用,没有则通过
  /// 注入的 opener 新开一个 channel,并对并发调用做去重
  /// (共享同一个 attach Future,避免重复开 channel)。
  Future<SftpClient> ensureClient() async {
    final existing = _sftpClient;
    if (existing != null) return existing;

    final pending = _pendingAttach;
    if (pending != null) return pending;

    final opener = _openClient;
    if (opener == null) {
      throw Exception('SFTP not attached: no channel and no opener configured');
    }
    final attachFuture = opener();
    _pendingAttach = attachFuture;
    try {
      _sftpClient = await attachFuture;
      return _sftpClient!;
    } catch (_) {
      _pendingAttach = null;
      rethrow;
    }
  }

  /// 清空 SFTP channel(SSH 断开/重连时调用),之后各操作会重新 attach。
  void detach() {
    _sftpClient = null;
    _pendingAttach = null;
  }

  /// 执行一个 SFTP 操作:未 attach 先 ensureClient;若中途 channel 失效(抛错),
  /// 则 detach 重建后重试一次。
  Future<T> withReattach<T>(Future<T> Function(SftpClient client) op) async {
    try {
      final client = await ensureClient();
      return await op(client);
    } catch (e, st) {
      debugPrint('[SFTP] withReattach 失败: $e\n$st');
      detach();
      final client = await ensureClient();
      return op(client);
    }
  }

  Future<List<SftpFileItem>> listDirectory(String path) async {
    return withReattach((client) async {
      final entries = await client.listdir(path);
      debugPrint('[SFTP] listDirectory($path) -> ${entries.length} 项');

      final items = <SftpFileItem>[];
      for (final entry in entries) {
        final name = entry.filename;
        if (name == '.' || name == '..') continue;
        final fullPath = p.posix.join(path, name);
        final attrs = entry.attr;
        final isDir = attrs.isDirectory;

        SftpEntryType entryType;
        switch (attrs.type) {
          case SftpFileType.directory:
            entryType = SftpEntryType.directory;
            break;
          case SftpFileType.symbolicLink:
            entryType = SftpEntryType.symbolicLink;
            break;
          case SftpFileType.blockDevice:
            entryType = SftpEntryType.blockDevice;
            break;
          case SftpFileType.characterDevice:
            entryType = SftpEntryType.characterDevice;
            break;
          case SftpFileType.pipe:
            entryType = SftpEntryType.pipe;
            break;
          case SftpFileType.socket:
            entryType = SftpEntryType.socket;
            break;
          case SftpFileType.whiteout:
            entryType = SftpEntryType.whiteout;
            break;
          default:
            entryType = isDir ? SftpEntryType.directory : SftpEntryType.regularFile;
        }

        items.add(SftpFileItem(
          name: name,
          path: fullPath,
          isDirectory: isDir,
          size: attrs.size ?? 0,
          modifiedAt: attrs.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000)
              : null,
          accessAt: attrs.accessTime != null
              ? DateTime.fromMillisecondsSinceEpoch(attrs.accessTime! * 1000)
              : null,
          permissions: attrs.mode?.value ?? 0,
          uid: attrs.userID,
          gid: attrs.groupID,
          entryType: entryType,
        ));
      }

      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      for (final item in items) {
        debugPrint('[SFTP] 条目: ${item.name} '
            '(type=${item.entryType}, dir=${item.isDirectory}, '
            'size=${item.size}, modifiedAt=${item.modifiedAt}, '
            'mode=${item.permissions}, uid=${item.uid}, gid=${item.gid})');
      }
      debugPrint('[SFTP] listDirectory($path) 返回 ${items.length} 项');

      return items;
    });
  }

  Future<void> createDirectory(String path) async {
    await withReattach((client) => client.mkdir(path));
  }

  Future<void> uploadFile(String localPath, String remotePath,
      {void Function(SftpProgress)? onProgress}) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');

    final file = File(localPath);
    if (!file.existsSync()) throw Exception('Local file not found: $localPath');

    final fileSize = file.lengthSync();
    final fileName = p.basename(localPath);
    final transferId = 'upload_${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final progress = SftpProgress(fileName: fileName, totalBytes: fileSize);
    _activeTransfers[transferId] = progress;
    _progressController.add(Map.unmodifiable(_activeTransfers));

    try {
      final remoteFile = await _sftpClient!.open(
        remotePath,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
      );

      const chunkSize = 32768;
      int offset = 0;
      final raf = file.openSync(mode: FileMode.read);

      while (offset < fileSize) {
        if (progress.cancelled) {
          await remoteFile.close();
          raf.closeSync();
          try {
            await _sftpClient!.remove(remotePath);
          } catch (_) {}
          return;
        }

        final remaining = fileSize - offset;
        final currentChunk = remaining < chunkSize ? remaining : chunkSize;
        final data = raf.readSync(currentChunk);

        await remoteFile.writeBytes(Uint8List.fromList(data), offset: offset);
        offset += currentChunk;
        progress.transferredBytes = offset;
        onProgress?.call(progress);
        _progressController.add(Map.unmodifiable(_activeTransfers));
      }

      raf.closeSync();
      await remoteFile.close();
      progress.completed = true;
    } catch (e) {
      progress.error = e.toString();
      rethrow;
    } finally {
      _activeTransfers.remove(transferId);
      _progressController.add(Map.unmodifiable(_activeTransfers));
    }
  }

  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(SftpProgress)? onProgress}) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');

    final remoteStat = await _sftpClient!.stat(remotePath);
    final fileSize = remoteStat.size ?? 0;
    final fileName = p.basename(remotePath);
    final transferId = 'download_${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final progress = SftpProgress(fileName: fileName, totalBytes: fileSize);
    _activeTransfers[transferId] = progress;
    _progressController.add(Map.unmodifiable(_activeTransfers));

    try {
      final remoteFile = await _sftpClient!.open(remotePath, mode: SftpFileOpenMode.read);
      final sink = File(localPath).openSync(mode: FileMode.write);

      const chunkSize = 32768;
      int offset = 0;

      while (offset < fileSize) {
        if (progress.cancelled) {
          sink.closeSync();
          await remoteFile.close();
          try {
            File(localPath).deleteSync();
          } catch (_) {}
          return;
        }

        final remaining = fileSize - offset;
        final currentChunk = remaining < chunkSize ? remaining : chunkSize;
        final data = await remoteFile.readBytes(length: currentChunk, offset: offset);
        sink.writeFromSync(data.toList());
        offset += currentChunk;
        progress.transferredBytes = offset;
        onProgress?.call(progress);
        _progressController.add(Map.unmodifiable(_activeTransfers));
      }

      sink.closeSync();
      await remoteFile.close();
      progress.completed = true;
    } catch (e) {
      progress.error = e.toString();
      rethrow;
    } finally {
      _activeTransfers.remove(transferId);
      _progressController.add(Map.unmodifiable(_activeTransfers));
    }
  }

  void cancelTransfer(String transferId) {
    final progress = _activeTransfers[transferId];
    if (progress != null) {
      progress.cancelled = true;
      _progressController.add(Map.unmodifiable(_activeTransfers));
    }
  }

  void cancelAllTransfers() {
    for (final progress in _activeTransfers.values) {
      progress.cancelled = true;
    }
    _progressController.add(Map.unmodifiable(_activeTransfers));
  }

  Future<void> remove(String path, {bool recursive = false}) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    if (recursive) {
      await _removeRecursive(path);
    } else {
      await _sftpClient!.remove(path);
    }
  }

  Future<void> _removeRecursive(String path) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    final entries = await _sftpClient!.listdir(path);
    for (final entry in entries) {
      final name = entry.filename;
      if (name == '.' || name == '..') continue;
      final fullPath = p.posix.join(path, name);
      if (entry.attr.isDirectory) {
        await _removeRecursive(fullPath);
      } else {
        await _sftpClient!.remove(fullPath);
      }
    }
    await _sftpClient!.rmdir(path);
  }

  Future<void> rename(String oldPath, String newPath) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    await _sftpClient!.rename(oldPath, newPath);
  }

  Future<String?> readFileContent(String remotePath, {int maxSize = 5 * 1024 * 1024}) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    try {
      final remoteFile = await _sftpClient!.open(remotePath, mode: SftpFileOpenMode.read);
      final stat = await _sftpClient!.stat(remotePath);
      final size = stat.size ?? 0;

      if (size > maxSize) {
        await remoteFile.close();
        return null;
      }

      final data = await remoteFile.readBytes(length: size);
      await remoteFile.close();
      return utf8.decode(data.toList(), allowMalformed: true);
    } catch (e) {
      return null;
    }
  }

  Future<void> writeFileContent(String remotePath, String content) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    final remoteFile = await _sftpClient!.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    final data = utf8.encode(content);
    await remoteFile.writeBytes(Uint8List.fromList(data));
    await remoteFile.close();
  }

  Future<int> getFileSize(String remotePath) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    final stat = await _sftpClient!.stat(remotePath);
    return stat.size ?? 0;
  }

  Future<bool> fileExists(String remotePath) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    try {
      await _sftpClient!.stat(remotePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Close the underlying SFTP channel. Call this when the service is
  /// destroyed to avoid leaking channels on the SSH connection.
  void close() {
    final client = _sftpClient;
    if (client != null) {
      try {
        client.close();
      } catch (_) {}
    }
    _sftpClient = null;
    _pendingAttach = null;
  }

  void dispose() {
    cancelAllTransfers();
    _progressController.close();
    _sftpClient = null;
    _pendingAttach = null;
  }
}
