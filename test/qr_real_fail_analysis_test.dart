import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart' as zx;

import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';

/// 用真实失败图片复现:分析尺寸/logo 占比,并对比多种解码策略。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dir = Directory('/home/zdart/文档/zebra.dart.xin/qr');
  final files = <File>[
    ...dir.listSync(recursive: true).whereType<File>(),
  ];

  test('real failing images analysis', () async {
    for (final f in files) {
      final bytes = f.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) {
        // ignore: avoid_print
        print('${f.path} → 无法解码为图片(${f.lengthSync()}B)');
        continue;
      }
      // ignore: avoid_print
      print('${f.path} ${image.width}x${image.height} ${f.lengthSync()}B');

      // 当前解码器
      final current = QrDecoder().decode(bytes);
      // ignore: avoid_print
      print('  当前解码器 → ${current == null ? "失败" : "成功: $current"}');

      // 直接 zxing(不经解码器预处理)
      final direct = _decodeDirect(bytes);
      // ignore: avoid_print
      print('  直接zxing → ${direct == null ? "失败" : "成功: $direct"}');
    }
  });
}

String? _decodeDirect(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final source = zx.RGBLuminanceSource(
    image.width,
    image.height,
    image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.bgra)
        .buffer
        .asInt32List(),
  );
  for (final s in [source, zx.InvertedLuminanceSource(source)]) {
    try {
      return zx
          .QRCodeReader()
          .decode(zx.BinaryBitmap(zx.GlobalHistogramBinarizer(s)))
          .text;
    } catch (_) {
      // 忽略
    }
  }
  return null;
}
