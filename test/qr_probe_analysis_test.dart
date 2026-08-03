import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart' as zx;

import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';

/// 探针:把失败图降采样成字符画,并尝试多种预处理策略,
/// 定位每张图失败的具体原因。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dir = Directory('/home/zdart/文档/zebra.dart.xin/qr/error');
  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('probe failing images', () {
    for (final f in files) {
      // ignore: avoid_print
      print('\n########## ${f.uri.pathSegments.last} ##########');
      final bytes = f.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) {
        // ignore: avoid_print
        print('无法解码');
        continue;
      }
      // ignore: avoid_print
      print('尺寸 ${image.width}x${image.height}');

      // 字符画:降采样到 96 宽
      _printAscii(image);

      // 策略探针
      final probes = <String, String?>{
        '当前解码器': QrDecoder().decode(bytes),
        '灰度+对比度拉伸': _tryStretch(bytes),
        '降采样0.5x': _tryDownscale(bytes, 0.5),
        '降采样0.33x': _tryDownscale(bytes, 0.33),
        '降采样0.25x': _tryDownscale(bytes, 0.25),
        '反色': _tryInvert(bytes),
        '预二值化(局部均值)': _tryLocalBinarize(bytes),
        'logo填白': _tryLogoFill(bytes, white: true),
        'logo填黑': _tryLogoFill(bytes, white: false),
      };
      for (final e in probes.entries) {
        // ignore: avoid_print
        print('  ${e.key.padRight(18)} → ${e.value ?? "失败"}');
      }
    }
  });
}

void _printAscii(img.Image image) {
  const cols = 96;
  final rows = (image.height * cols / image.width).round();
  final buf = StringBuffer();
  for (var y = 0; y < rows; y++) {
    final sy = (y * image.height / rows).round();
    for (var x = 0; x < cols; x++) {
      final sx = (x * image.width / cols).round();
      final p = image.getPixel(sx, sy);
      final lum = (p.r + p.g + p.b) / 3;
      final mx = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
      final mn = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
      final colored = mx - mn > 40;
      if (colored && mx > 60) {
        buf.write('C'); // 彩色(logo 等)
      } else if (lum < 60) {
        buf.write('#');
      } else if (lum < 130) {
        buf.write('+');
      } else if (lum < 200) {
        buf.write('.');
      } else {
        buf.write(' ');
      }
    }
    buf.writeln();
  }
  // ignore: avoid_print
  print(buf);
}

/// 灰度化 + 直方图对比度拉伸到 [0,255]。
String? _tryStretch(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final gray = img.grayscale(image);
  // 统计直方图,取 1%/99% 分位做线性拉伸
  final hist = List<int>.filled(256, 0);
  for (final p in gray) {
    hist[p.r.toInt()]++;
  }
  var total = gray.length;
  var lo = 0, hi = 255, acc = 0;
  for (var i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc >= total ~/ 100) {
      lo = i;
      break;
    }
  }
  acc = 0;
  for (var i = 255; i >= 0; i--) {
    acc += hist[i];
    if (acc >= total ~/ 100) {
      hi = i;
      break;
    }
  }
  if (hi <= lo) return null;
  for (final p in gray) {
    final v = ((p.r - lo) * 255 / (hi - lo)).round().clamp(0, 255);
    p.r = v;
    p.g = v;
    p.b = v;
  }
  return _decodeGray(gray);
}

String? _tryDownscale(Uint8List bytes, double factor) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final small = img.copyResize(
    image,
    width: (image.width * factor).round(),
    height: (image.height * factor).round(),
    interpolation: img.Interpolation.average,
  );
  return _decodeGray(small);
}

String? _tryInvert(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return _decodeGray(img.invert(image));
}

/// 局部均值二值化(自适应阈值),消除光照不均。
String? _tryLocalBinarize(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final gray = img.grayscale(image);
  final w = gray.width, h = gray.height;
  final out = img.Image(width: w, height: h);
  final win = 31;
  // 积分图
  final integral = List.generate(h + 1, (_) => List<int>.filled(w + 1, 0));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += gray.getPixel(x, y).r.toInt();
      integral[y + 1][x + 1] = integral[y][x + 1] + rowSum;
    }
  }
  for (var y = 0; y < h; y++) {
    final y0 = (y - win ~/ 2).clamp(0, h - 1);
    final y1 = (y + win ~/ 2).clamp(0, h - 1);
    for (var x = 0; x < w; x++) {
      final x0 = (x - win ~/ 2).clamp(0, w - 1);
      final x1 = (x + win ~/ 2).clamp(0, w - 1);
      final area = (y1 - y0 + 1) * (x1 - x0 + 1);
      final sum = integral[y1 + 1][x1 + 1] -
          integral[y0][x1 + 1] -
          integral[y1 + 1][x0] +
          integral[y0][x0];
      final mean = sum / area;
      final v = gray.getPixel(x, y).r < mean ? 0 : 255;
      out.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return _decodeGray(out);
}

/// 检测中心彩色 logo 区域并填白/填黑,绕过 logo 干扰。
String? _tryLogoFill(Uint8List bytes, {required bool white}) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final gray = img.grayscale(image);
  final w = gray.width, h = gray.height;
  final cx = w ~/ 2, cy = h ~/ 2;
  // 以中心为种子,找连续彩色区域边界
  var minX = cx, maxX = cx, minY = cy, maxY = cy;
  var changed = true;
  while (changed) {
    changed = false;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final p = gray.getPixel(x, y);
        final mx = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
        final mn = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
        if (mx - mn > 40 && mx > 60) {
          if (x > 0 && minX > x - 1) { minX = x - 1; changed = true; }
          if (x < w - 1 && maxX < x + 1) { maxX = x + 1; changed = true; }
          if (y > 0 && minY > y - 1) { minY = y - 1; changed = true; }
          if (y < h - 1 && maxY < y + 1) { maxY = y + 1; changed = true; }
        }
      }
    }
  }
  final area = (maxX - minX + 1) * (maxY - minY + 1);
  // 只有 logo 区域不是整幅图才处理
  if (area > 0 && area < w * h * 0.5) {
    final fill = white ? 255 : 0;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        gray.setPixelRgba(x, y, fill, fill, fill, 255);
      }
    }
    // ignore: avoid_print
    print('    [logo区域 (${minX},${minY})-(${maxX},${maxY}) ${area}px 已填${white ? "白" : "黑"}]');
  }
  return _decodeGray(gray);
}

/// 把灰度图转 zxing 亮度源解码(原始 + 反色各试一次)。
String? _decodeGray(img.Image gray) {
  final source = zx.RGBLuminanceSource(
    gray.width,
    gray.height,
    gray
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
