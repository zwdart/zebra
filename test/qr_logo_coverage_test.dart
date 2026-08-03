import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 分析失败图:定位三个定位角 → 模块尺寸 → logo 覆盖范围(模块数)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('analyze failing images', () {
    final dir = Directory('/home/zdart/文档/zebra.dart.xin/qr/error');
    for (final f in dir.listSync().whereType<File>()) {
      final image = img.decodeImage(f.readAsBytesSync());
      if (image == null) {
        // ignore: avoid_print
        print('${f.path}: 无法解码');
        continue;
      }
      // ignore: avoid_print
      print('=== ${f.uri.pathSegments.last} (${image.width}x${image.height}) ===');

      // 找黑色内容边界(QR 主体,不含静区)
      var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          final lum = (p.r + p.g + p.b) / 3;
          if (lum < 100) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      // ignore: avoid_print
      print('QR内容边界: ($minX,$minY)-($maxX,$maxY) 宽=${maxX - minX + 1} 高=${maxY - minY + 1}');

      // 统计"彩色"像素(logo 区域,非黑非白非灰)
      var colored = 0;
      var cx0 = image.width, cy0 = image.height, cx1 = -1, cy1 = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          final mx = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
          final mn = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
          if (mx - mn > 40 && mx > 60) {
            colored++;
            if (x < cx0) cx0 = x;
            if (x > cx1) cx1 = x;
            if (y < cy0) cy0 = y;
            if (y > cy1) cy1 = y;
          }
        }
      }
      // ignore: avoid_print
      print('彩色像素(logo): $colored 边界: ($cx0,$cy0)-($cx1,$cy1) 宽=${cx1 - cx0 + 1} 高=${cy1 - cy0 + 1}');
    }
  });
}
