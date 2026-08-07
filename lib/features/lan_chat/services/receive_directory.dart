import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../utils/zebra_paths.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/file_transfer_session.dart' show kSmallFileThresholdBytes;

/// 接收文件的保存目录策略
///
/// 目标:全平台不需要权限、用户可直接访问进入的目录。
/// - Android:通过 MediaStore 写入系统"下载"目录(Android 10+ 无需任何权限,
///   文件直接出现在下载里,用户可在文件管理器直接访问);
///   失败时降级到应用外部目录(也无需权限)。
/// - 桌面端(Linux/Windows/macOS):系统文档目录,无需权限,用户可直接访问。
/// - iOS:应用文档目录(配合 Info.plist 的 UIFileSharingEnabled,
///   可在"文件"App 中直接访问)。
///
/// 接收过程写入 `<name>.<transferId>.part` 临时文件(低内存落盘),
/// 完成时转正为最终文件(无断点续传,方案 A 简化)。
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

  /// 打开"接收文件"目录(聊天页"文件夹"菜单入口)。
  /// Android 优先打开系统"下载"目录(MediaStore,无需权限);
  /// 其余平台打开应用文档目录下的 zebra_received。
  /// 目录不存在时先创建再打开,避免打开失败;创建/打开失败返回 false。
  static Future<bool> openReceivedFolder() async {
    // Android:系统"下载"目录(收到的文件默认都在那里)
    if (Platform.isAndroid) {
      final ok = await openDownloadsFolder();
      if (ok) return true;
      // 降级到应用文档目录
    }
    try {
      final dir = await ZebraPaths.received;
      // 目录不存在时先创建,避免打开不存在的路径
      await dir.create(recursive: true);
      final ok = await launchUrl(Uri.directory(dir.path));
      debugPrint('[ReceiveDirectory] openReceivedFolder -> ${dir.path} ok=$ok');
      return ok;
    } catch (e) {
      debugPrint('[ReceiveDirectory] openReceivedFolder failed: $e');
      return false;
    }
  }

  /// 创建接收中的临时 .part 文件,返回其路径。
  /// 已存在同名 .part(断点续传)时直接复用,便于追加写入。
  /// [transferId] 来自网络不可信,先消毒再拼入文件名,防止路径穿越。
  static Future<String> createPartFile(
      String transferId, String fileName) async {
    final dir = await ZebraPaths.received;
    await dir.create(recursive: true);
    final safeName = _safeName(fileName);
    // 只保留安全字符,杜绝 ../ 等路径穿越
    final safeTid = transferId.replaceAll(RegExp(r'[^0-9a-zA-Z\-]'), '_');
    final partPath = p.join(dir.path, '$safeName.$safeTid.part');
    final file = File(partPath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return partPath;
  }

  /// 将 .part 临时文件转正为最终文件,返回展示/定位路径。
  /// Android 小文件走 MediaStore(整文件读入,内存可承受);大文件优先流式写入
  /// MediaStore 下载目录(用户可见,免权限),失败降级流式复制到文档目录
  /// (避免整文件读入内存导致 OOM);其余平台直接改名;失败返回空串。
  static Future<String> finalizePartFile(
      String partPath, String fileName) async {
    final part = File(partPath);
    if (!await part.exists()) return '';
    if (Platform.isAndroid) {
      final size = await part.length();
      if (size > kSmallFileThresholdBytes) {
        // 大文件:优先流式写入 MediaStore 下载目录(与最终接收文件一致,用户可见)
        try {
          final result = await _channel.invokeMapMethod<String, String>(
            'saveReceivedFileFromPath',
            {'partPath': partPath, 'fileName': fileName},
          );
          final path = result?['path'];
          if (path != null && path.isNotEmpty) {
            await part.delete();
            debugPrint('[ReceiveDirectory] finalize part -> MediaStore: $path');
            return path;
          }
        } catch (e) {
          debugPrint('[ReceiveDirectory] finalize part to MediaStore failed: $e');
        }
        // 降级:文档目录流式复制(私有但保底,不整读内存)
        return _finalizePartToDocumentsStream(part, fileName);
      }
      try {
        final bytes = await part.readAsBytes();
        final saved = await saveReceivedFile(bytes, fileName);
        await part.delete();
        return saved;
      } catch (e) {
        debugPrint('[ReceiveDirectory] finalize part on Android failed: $e');
        return '';
      }
    }
    final dir = await ZebraPaths.received;
    final safeName = _safeName(fileName);
    var target = File(p.join(dir.path, safeName));
    if (await target.exists()) {
      target = File(p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}-$safeName'));
    }
    await part.rename(target.path);
    debugPrint('[ReceiveDirectory] finalized part -> ${target.path}');
    return target.path;
  }

  /// Android 大文件转正:流式复制 .part 到应用文档目录(避免整文件读入内存 OOM)
  static Future<String> _finalizePartToDocumentsStream(
      File part, String fileName) async {
    try {
      final dir = await ZebraPaths.received;
      await dir.create(recursive: true);
      final safeName = _safeName(fileName);
      var target = File(p.join(dir.path, safeName));
      if (await target.exists()) {
        target = File(
            p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}-$safeName'));
      }
      await part.openRead().pipe(target.openWrite());
      await part.delete();
      debugPrint('[ReceiveDirectory] finalized part (stream) -> ${target.path}');
      return target.path;
    } catch (e) {
      debugPrint('[ReceiveDirectory] finalize part stream failed: $e');
      return '';
    }
  }

  /// 删除 .part 临时文件(取消/失败时清理)
  static Future<void> deletePartFile(String partPath) async {
    try {
      final file = File(partPath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[ReceiveDirectory] delete part failed: $e');
    }
  }

  static String _safeName(String fileName) =>
      fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static Future<String> _saveToDocuments(
      List<int> bytes, String fileName) async {
    final dir = await ZebraPaths.received;
    await dir.create(recursive: true);

    final safeName = _safeName(fileName);
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
