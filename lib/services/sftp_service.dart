import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
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
  final Map<String, SftpProgress> _activeTransfers = {};
  final StreamController<Map<String, SftpProgress>> _progressController =
      StreamController<Map<String, SftpProgress>>.broadcast();

  Stream<Map<String, SftpProgress>> get progressStream => _progressController.stream;
  Map<String, SftpProgress> get activeTransfers => Map.unmodifiable(_activeTransfers);

  void attach(SftpClient client) {
    _sftpClient = client;
  }

  Future<List<SftpFileItem>> listDirectory(String path) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    final entries = await _sftpClient!.listdir(path);

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

    return items;
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

  Future<void> createDirectory(String path) async {
    if (_sftpClient == null) throw Exception('SFTP not initialized');
    await _sftpClient!.mkdir(path);
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

  void dispose() {
    cancelAllTransfers();
    _progressController.close();
    _sftpClient = null;
  }
}
