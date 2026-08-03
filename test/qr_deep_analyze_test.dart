import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 深度分析失败图:
/// ① 静区是否存在(四角颜色);
/// ② 通过定位角 1:1:3:1:1 黑色游程推算模块尺寸与二维码维度;
/// ③ logo 区域的颜色与几何。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deep analyze failing images', () {
    final dir = Directory('/home/zdart/文档/zebra.dart.xin/qr/error');
    for (final f in dir.listSync().whereType<File>()) {
      final image = img.decodeImage(f.readAsBytesSync());
      if (image == null) continue;
      // ignore: avoid_print
      print('=== ${f.uri.pathSegments.last} ===');

      final c = (int x, int y) {
        final p = image.getPixel(x, y);
        return '(${p.r},${p.g},${p.b})';
      };
      final w = image.width, h = image.height;
      // ignore: avoid_print
      print('四角: TL${c(3, 3)} TR${c(w - 4, 3)} BL${c(3, h - 4)} BR${c(w - 4, h - 4)} '
          '中心${c(w ~/ 2, h ~/ 2)}');

      // 沿中轴线扫黑色游程,找 1:1:3:1:1 定位角
      var yMid = h ~/ 2;
      List<int> runs = [];
      var cur = 0, curColor = 0;
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, yMid);
        final dark = (p.r + p.g + p.b) / 3 < 128;
        final bit = dark ? 1 : 0;
        if (bit == curColor) {
          cur++;
        } else {
          runs.add(cur);
          cur = 1;
          curColor = bit;
        }
      }
      runs.add(cur);
      // ignore: avoid_print
      print('中轴游程(前40): ${runs.take(40).join(",")}');

      // 估算模块尺寸:取连续黑游程中出现次数最多的中位数
      final darkRuns =
          [for (var i = 0; i < runs.length; i += 2) runs[i]].where((r) => r > 0).toList()
            ..sort();
      if (darkRuns.isNotEmpty) {
        final median = darkRuns[darkRuns.length ~/ 2];
        // ignore: avoid_print
        print('黑色游程中位数≈$median px (模块参考), 全部: ${darkRuns.take(12).join(",")}');
      }
    }
  });
}
