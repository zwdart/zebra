import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 接收文件的保存目录策略
///
/// 目标:全平台不需要权限、用户可直接访问进入的目录。
/// - Android:通过 MediaStore 写入系统"下载"目录(Android 10+ 无需任何权限,
///   文件直接出现在下载里,用户可在文件管理器直接访问);
///   失败时降级到应用外部目录(也无需权限)。
/// - 桌面端(Linux/Windows/macOS):系统文档目录,无需权限,用户可直接访问。
/// - iOS:应用文档目录(配合 Info.plist 的 UIFileSharingEnabled,
///   可在"文件"App 中直接访问)。
class ReceiveDirectory {
  static const MethodChannel _channel =
      MethodChannel('xin.dart.zebra/receive_file');

  /// 保存接收到的文件字节,返回用于展示/定位的路径。
  ///
  /// Android 走 MediaStore 时返回展示路径(如 `Download/zebra/x.pdf`,
  /// 不是真实文件路径,点击时打开系统下载目录);
  /// 其余平台/降级路径返回真实文件路径(点击时打开所在目录)。
  static Future<String> saveReceivedFile(
      List<int> bytes, String fileName) async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMapMethod<String, String>(
          'saveReceivedFile',
          {'bytes': Uint8List.fromList(bytes), 'fileName': fileName},
        );
        final path = result?['path'];
        if (path != null && path.isNotEmpty) {
          debugPrint('[ReceiveDirectory] saved via MediaStore: $path');
          return path;
        }
      } catch (e) {
        debugPrint('[ReceiveDirectory] Android save failed: $e');
      }
    }
    // 桌面端/iOS/Android 降级:系统文档目录
    return _saveToDocuments(bytes, fileName);
  }

  /// 在 Android 上打开系统"下载"目录(收到的文件默认都在那里)。
  /// 返回是否成功打开;非 Android 平台直接返回 false。
  static Future<bool> openDownloadsFolder() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('openDownloadsFolder') ?? false;
    } catch (e) {
      debugPrint('[ReceiveDirectory] openDownloadsFolder failed: $e');
      return false;
    }
  }

  static Future<String> _saveToDocuments(
      List<int> bytes, String fileName) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'zebra_received'));
    await dir.create(recursive: true);

    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var target = File(p.join(dir.path, safeName));
    if (await target.exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      target = File(p.join(dir.path, '$stamp-$safeName'));
    }
    await target.writeAsBytes(bytes, flush: true);
    debugPrint('[ReceiveDirectory] saved to documents: ${target.path}');
    return target.path;
  }
}
