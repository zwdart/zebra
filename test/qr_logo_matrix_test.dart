import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:zebra/features/qr_tool/models/qr_style_config.dart';
import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';
import 'package:zebra/features/qr_tool/repositories/qr_generator.dart';

/// ① 真实失败图:把 logo 区域涂成白色后能否解出?
///    - 能 → 数据没丢,是 logo 覆盖 + 二值化问题(可救);
///    - 不能 → 生成时数据已被破坏(不可救,需重生成)。
/// ② logo 生成矩阵:纠错级别 × 内容长度,logo 固定 0.2 scale。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('white-out logo region on real failing images', () {
    final dir = Directory('/home/zdart/文档/zebra.dart.xin/qr/error');
    for (final f in dir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) continue;
      // 找出彩色区域(logo)并涂白
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          final mx = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
          final mn = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
          if (mx - mn > 40 && mx > 60) {
            p
              ..r = 255
              ..g = 255
              ..b = 255;
          }
        }
      }
      final withLogo = QrDecoder().decode(bytes);
      final whitened = QrDecoder().decode(img.encodePng(image));
      // ignore: avoid_print
      print('${f.uri.pathSegments.last}: 原图=${withLogo == null ? "失败" : "成功"} '
          '涂白logo后=${whitened == null ? "失败" : "成功: $whitened"}');
    }
  });

  test('logo generation matrix: error level x content length', () async {
    final logo = img.Image(width: 96, height: 96);
    for (var y = 0; y < 96; y++) {
      for (var x = 0; x < 96; x++) {
        if (x < 8 || y < 8 || x >= 88 || y >= 88) {
          logo.setPixelRgba(x, y, 255, 255, 255, 255);
        } else if (x < 48) {
          logo.setPixelRgba(x, y, 33, 150, 243, 255);
        } else {
          logo.setPixelRgba(x, y, 21, 101, 192, 255);
        }
      }
    }
    final logoPng = img.encodePng(logo);

    const contents = <String, String>{
      '短内容': 'https://a.b',
      '中内容': 'https://example.com/path/to/page?id=123456&name=zebra',
      '长中文': '这是一个比较长的中文内容,用来测试二维码在不同长度下的表现,请务必确认能够正常识别,谢谢配合。',
    };
    for (final e in contents.entries) {
      for (final level in QrErrorLevel.values) {
        final config = QrStyleConfig(
          data: e.value,
          errorLevel: level,
          logoBytes: logoPng,
          quietZone: 4,
        );
        final bytes = await QrGenerator().exportPng(config);
        final decoded = QrDecoder().decode(bytes);
        // ignore: avoid_print
        print('${e.key} + $level → ${decoded == e.value ? "可识别" : "失败"}');
      }
    }
  });
}
