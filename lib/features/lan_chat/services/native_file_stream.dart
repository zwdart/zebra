import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// 原生系统选择器选中的一个文件(直读流,不复制到缓存)。
class NativePickedFile {
  const NativePickedFile({
    required this.uri,
    required this.name,
    required this.size,
  });

  /// Android: content:// URI;iOS: file:// security-scoped URL
  final String uri;
  final String name;
  final int size;
}

/// 发送侧"直读流"通道:绕过 file_picker 的"复制到缓存"步骤,
/// 通过原生 platform channel 直接流式读取用户选中的原文件。
///
/// - Android: SAF(ACTION_OPEN_DOCUMENT)→ ContentResolver 流式读,零复制;
///   选文件时已 takePersistableUriPermission,支持跨重启断点续传。
/// - iOS: UIDocumentPicker(.open 模式,不导入沙盒)→ FileHandle 读原文件;
///   security-scoped 访问由原生侧管理(start/stopAccessing)。
/// - 桌面/Web 不支持,调用方应回退 file_picker(路径方案)。
///
/// 断点续传语义:[openRead] 的 [offset] 参数让原生侧"重开流并跳过/seek 到
/// 已传字节",因此同一个 URI 可以被反复打开,与 RandomAccessFile 定位等价。
class NativeFileStream {
  static const MethodChannel _channel = MethodChannel('xin.dart.zebra/native_file');

  /// 每块读取大小,与发送侧路径方案对齐(256KB):
  /// 更细粒度的 TCP 背压与接收端事件循环交错,避免接收端 pending 突发堆积
  static const int defaultChunkSize = 256 * 1024;

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// 打开系统文件选择器(多选),返回用户选中的文件;空列表表示取消。
  static Future<List<NativePickedFile>> pickFiles() async {
    final raw = await _channel.invokeListMethod<dynamic>('pickFiles');
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((m) => NativePickedFile(
              uri: m['uri'] as String? ?? '',
              name: m['name'] as String? ?? 'file',
              size: (m['size'] as num?)?.toInt() ?? -1,
            ))
        .where((f) => f.uri.isNotEmpty)
        .toList();
  }

  /// 打开 [uri] 的读取流;重开时通过 [offset] 跳过已传字节(断点续传)。
  /// 以 [chunkSize] 为块大小逐块产出数据,EOF 结束;流关闭时自动释放原生句柄。
  static Stream<List<int>> openRead(
    String uri, {
    int offset = 0,
    int chunkSize = defaultChunkSize,
  }) async* {
    final handle = await _channel.invokeMethod<int>('openRead', {
      'uri': uri,
      'offset': offset,
    });
    if (handle == null) {
      throw StateError('openRead failed: $uri');
    }
    try {
      while (true) {
        final bytes = await _channel.invokeMethod<Uint8List>(
          'readChunk',
          {'handle': handle, 'count': chunkSize},
        );
        if (bytes == null || bytes.isEmpty) break;
        yield bytes;
      }
    } finally {
      // 兜底释放原生句柄(正常 EOF / 取消 / 出错统一走这里)
      try {
        await _channel.invokeMethod<void>('closeRead', {'handle': handle});
      } catch (_) {}
    }
  }

  /// 关闭全部原生句柄并释放 security-scoped 访问(会话级清理兜底)。
  static Future<void> releaseAll() async {
    try {
      await _channel.invokeMethod<void>('releaseAll');
    } catch (_) {}
  }
}
