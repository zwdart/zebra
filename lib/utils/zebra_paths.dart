import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Centralized export/download path manager.
/// All files are stored under appDocumentsDir/zebra.dart.xin/subdir/.
/// Uses getApplicationDocumentsDirectory - no permissions needed, cross-platform.
class ZebraPaths {
  ZebraPaths._();

  static const _root = 'zebra.dart.xin';

  /// Base directory: appDocumentsDir/zebra.dart.xin/
  static Future<Directory> get root async {
    final dir = await getApplicationDocumentsDirectory();
    final zebraDir = Directory(p.join(dir.path, _root));
    if (!await zebraDir.exists()) {
      await zebraDir.create(recursive: true);
    }
    return zebraDir;
  }

  /// RSS exports: appDocumentsDir/zebra.dart.xin/rss/
  static Future<Directory> get rss async {
    final base = await root;
    final rssDir = Directory(p.join(base.path, 'rss'));
    if (!await rssDir.exists()) {
      await rssDir.create(recursive: true);
    }
    return rssDir;
  }

  /// Diary exports: appDocumentsDir/zebra.dart.xin/diary/
  static Future<Directory> get diary async {
    final base = await root;
    final diaryDir = Directory(p.join(base.path, 'diary'));
    if (!await diaryDir.exists()) {
      await diaryDir.create(recursive: true);
    }
    return diaryDir;
  }

  /// SSH downloads: appDocumentsDir/zebra.dart.xin/ssh/
  static Future<Directory> get ssh async {
    final base = await root;
    final sshDir = Directory(p.join(base.path, 'ssh'));
    if (!await sshDir.exists()) {
      await sshDir.create(recursive: true);
    }
    return sshDir;
  }

  /// LAN chat received files: appDocumentsDir/zebra.dart.xin/zebra_received/
  static Future<Directory> get received async {
    final base = await root;
    final recvDir = Directory(p.join(base.path, 'zebra_received'));
    if (!await recvDir.exists()) {
      await recvDir.create(recursive: true);
    }
    return recvDir;
  }

  /// Get a file path under a specific subdirectory.
  static Future<String> filePath(String subdirectory, String filename) async {
    final dir = await root;
    final subDir = Directory(p.join(dir.path, subdirectory));
    if (!await subDir.exists()) {
      await subDir.create(recursive: true);
    }
    return p.join(subDir.path, filename);
  }
}
