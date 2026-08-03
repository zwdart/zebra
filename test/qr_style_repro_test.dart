import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:zebra/features/qr_tool/models/qr_style_config.dart';
import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';
import 'package:zebra/features/qr_tool/repositories/qr_generator.dart';

/// 样式矩阵回归:所有样式组合(形状/密度/渐变/颜色/反色/静区)生成的
/// 二维码都必须能被自己的识别功能解出。
///
/// 修复前以下组合会识别失败:
/// ① 识别端像素字节序错误(abgr)导致彩色/渐变/浅色/反色样式失败;
/// ② squares 密度 < 1 或圆角 > 0.1 时定位角被样式破坏,纯 Dart zxing
///    检测不到 1:1:3:1:1 结构(导出时重绘为标准定位角解决)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('style matrix round-trips through the decoder', () async {
    const data = 'https://example.com/style-matrix';
    final configs = <String, QrStyleConfig>{
      // 形状 × 密度
      for (final shape in QrShapeStyle.values)
        for (final density in const [1.0, 0.7, 0.5, 0.3])
          'shape=$shape density=$density':
              QrStyleConfig(data: data, shape: shape, density: density),
      // 渐变 × 形状
      for (final shape in QrShapeStyle.values)
        'gradient $shape': QrStyleConfig(
          data: data,
          shape: shape,
          useGradient: true,
          gradientColors: const [Color(0xFF000000), Color(0xFF444444)],
        ),
      // 颜色 / 反色 / 静区
      'fg grey': const QrStyleConfig(data: data, fgColor: Color(0xFF9E9E9E)),
      'inverted': const QrStyleConfig(
          data: data, fgColor: Color(0xFFFFFFFF), bgColor: Color(0xFF000000)),
      'fg blue': const QrStyleConfig(data: data, fgColor: Color(0xFF1565C0)),
      'fg lightblue':
          const QrStyleConfig(data: data, fgColor: Color(0xFF90CAF9)),
      'bg light grey':
          const QrStyleConfig(data: data, bgColor: Color(0xFFEEEEEE)),
      'quietZone 0': const QrStyleConfig(data: data, quietZone: 0),
      'quietZone 4': const QrStyleConfig(data: data, quietZone: 4),
    };
    for (final entry in configs.entries) {
      final bytes = await QrGenerator().exportPng(entry.value);
      final decoded = QrDecoder().decode(bytes);
      expect(decoded, data, reason: '样式组合 "${entry.key}" 识别失败');
    }
  });
}
