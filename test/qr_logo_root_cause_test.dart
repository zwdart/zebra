import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart' as zx;

import 'package:zebra/features/qr_tool/models/qr_style_config.dart';
import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';
import 'package:zebra/features/qr_tool/repositories/qr_generator.dart';

/// ① 用自适应阈值(积分图)对真实失败图再试一次——判断是"数据被破坏"
///    还是"二值化不够健壮";
/// ② 用不同纠错级别 × logo 重新生成,找出能识别的最小纠错级别。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real failing images with adaptive binarization', () {
    final dir = Directory('/home/zdart/文档/zebra.dart.xin/qr/error');
    for (final f in dir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      final current = QrDecoder().decode(bytes);
      final adaptive = adaptiveDecode(bytes);
      // ignore: avoid_print
      print('${f.uri.pathSegments.last}: 当前=${current == null ? "失败" : "成功"} '
          '自适应=${adaptive == null ? "失败" : "成功: $adaptive"}');
    }
  });

  test('logo round-trip across error levels and scales', () async {
    const data = 'https://example.com/logo-test';
    // 蓝色立方体风格的 logo(带白边),接近用户实际用的图
    final logo = img.Image(width: 96, height: 96);
    for (var y = 0; y < 96; y++) {
      for (var x = 0; x < 96; x++) {
        final whiteRing =
            x < 8 || y < 8 || x >= 88 || y >= 88;
        if (whiteRing) {
          logo.setPixelRgba(x, y, 255, 255, 255, 255);
        } else if (x < 48) {
          logo.setPixelRgba(x, y, 33, 150, 243, 255); // 蓝
        } else {
          logo.setPixelRgba(x, y, 21, 101, 192, 255); // 深蓝
        }
      }
    }
    final logoPng = img.encodePng(logo);

    for (final level in QrErrorLevel.values) {
      final config = QrStyleConfig(
        data: data,
        errorLevel: level,
        logoBytes: logoPng,
        quietZone: 4,
      );
      final bytes = await QrGenerator().exportPng(config);
      final decoded = QrDecoder().decode(bytes);
      // ignore: avoid_print
      print('logo 0.2 scale + $level → ${decoded == data ? "可识别" : "失败"}');
    }
  });
}

/// 积分图自适应阈值二值化(与之前原型一致)。
String? adaptiveDecode(Uint8List bytes, {int radius = 16, double k = 0.9}) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  const maxDimension = 2048;
  if (image.width > maxDimension || image.height > maxDimension) {
    image = img.copyResize(
      image,
      width: image.width > image.height ? maxDimension : null,
      height: image.width > image.height ? null : maxDimension,
      interpolation: img.Interpolation.average,
    );
  }
  final gray = image.convert(numChannels: 1).getBytes();
  final w = image.width, h = image.height;
  final pw = w + 1;
  final integral = Int32List(pw * (h + 1));
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final iRow = (y + 1) * pw;
    final iPrev = y * pw;
    for (var x = 0; x < w; x++) {
      integral[iRow + x + 1] = gray[row + x] +
          integral[iPrev + x + 1] +
          integral[iRow + x] -
          integral[iPrev + x];
    }
  }
  final out = Int32List(w * h);
  final k10 = (k * 10).round();
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final y0 = (y - radius).clamp(0, h - 1);
    final y1 = (y + radius).clamp(0, h - 1) + 1;
    final rowTop = y0 * pw;
    final rowBot = y1 * pw;
    for (var x = 0; x < w; x++) {
      final x0 = (x - radius).clamp(0, w - 1);
      final x1 = (x + radius).clamp(0, w - 1) + 1;
      final area = (x1 - x0) * (y1 - y0);
      final sum = integral[rowBot + x1] -
          integral[rowTop + x1] -
          integral[rowBot + x0] +
          integral[rowTop + x0];
      final mean = sum ~/ area;
      final black = gray[row + x] * 10 <= mean * k10;
      out[row + x] = black ? 0xFF000000 : 0xFFFFFFFF;
    }
  }
  final source = zx.RGBLuminanceSource(w, h, out);
  for (final s in [source, zx.InvertedLuminanceSource(source)]) {
    try {
      return zx
          .QRCodeReader()
          .decode(zx.BinaryBitmap(zx.GlobalHistogramBinarizer(s)))
          .text;
    } catch (_) {
      // 继续尝试
    }
  }
  return null;
}
