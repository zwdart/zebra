import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zebra/features/qr_tool/models/qr_style_config.dart';
import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';
import 'package:zebra/features/qr_tool/repositories/qr_generator.dart';

/// 模拟"修复前生成的旧图片":用 toImageAsBytes 直接渲染(绕过定位角重绘,
/// 即旧版 exportPng 的行为),再用修复后的 QrDecoder 识别。
Future<String?> renderOldWay(QrStyleConfig config) async {
  final qrCode = QrCode.fromData(
    data: config.data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(qrCode);
  final decoration = QrGenerator().buildDecoration(config);
  final byteData = await qrImage.toImageAsBytes(
    size: 512,
    format: ui.ImageByteFormat.png,
    decoration: decoration,
  );
  return QrDecoder().decode(byteData!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old-style images with new decoder', () async {
    const data = 'https://example.com/old-image';

    // 旧图:彩色(识别端修复应生效)
    final colorOld = await renderOldWay(
      const QrStyleConfig(data: data, fgColor: ui.Color(0xFF1565C0)),
    );
    // 旧图:反色(识别端修复应生效)
    final invertedOld = await renderOldWay(
      const QrStyleConfig(
          data: data, fgColor: ui.Color(0xFFFFFFFF), bgColor: ui.Color(0xFF000000)),
    );
    // 旧图:圆角(定位角已被样式破坏,识别端修复无效)
    final roundedOld = await renderOldWay(
      const QrStyleConfig(data: data, shape: QrShapeStyle.rounded),
    );
    // 旧图:密度 0.5(同上)
    final densityOld = await renderOldWay(
      const QrStyleConfig(data: data, density: 0.5),
    );

    // ignore: avoid_print
    print('旧彩色图  →  ${colorOld == data ? "可识别" : "失败($colorOld)"}');
    // ignore: avoid_print
    print('旧反色图  →  ${invertedOld == data ? "可识别" : "失败($invertedOld)"}');
    // ignore: avoid_print
    print('旧圆角图  →  ${roundedOld == data ? "可识别" : "失败($roundedOld)"}');
    // ignore: avoid_print
    print('旧低密度图 →  ${densityOld == data ? "可识别" : "失败($densityOld)"}');
  });
}
