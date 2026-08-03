import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zebra/features/qr_tool/models/qr_style_config.dart';
import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';
import 'package:zebra/features/qr_tool/repositories/qr_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generated QR PNG round-trips through the decoder', () async {
    const data = 'hello zebra 你好';
    final config = const QrStyleConfig(data: data);
    final bytes = await QrGenerator().exportPng(config);
    expect(bytes, isNotNull);
    final decoded = QrDecoder().decode(bytes);
    expect(decoded, data);
  });

  test('Chinese-only content decodes', () async {
    const data = '你好世界';
    final config = const QrStyleConfig(data: data);
    final bytes = await QrGenerator().exportPng(config);
    final decoded = QrDecoder().decode(bytes);
    // ignore: avoid_print
    print('decoded: "$decoded"');
    expect(decoded, data);
  });

  test('colored foreground decodes', () async {
    const data = 'hello color';
    const config = QrStyleConfig(data: data, fgColor: Color(0xFF1565C0));
    final bytes = await QrGenerator().exportPng(config);
    final decoded = QrDecoder().decode(bytes);
    // ignore: avoid_print
    print('decoded: "$decoded"');
    expect(decoded, data);
  });

  test('gradient foreground decodes', () async {
    const data = 'hello gradient';
    const config = QrStyleConfig(
      data: data,
      useGradient: true,
      gradientColors: [Color(0xFF000000), Color(0xFF333333)],
    );
    final bytes = await QrGenerator().exportPng(config);
    final decoded = QrDecoder().decode(bytes);
    // ignore: avoid_print
    print('decoded: "$decoded"');
    expect(decoded, data);
  });

  test('dots shape decodes', () async {
    const data = 'hello dots';
    const config = QrStyleConfig(data: data, shape: QrShapeStyle.dots);
    final bytes = await QrGenerator().exportPng(config);
    final decoded = QrDecoder().decode(bytes);
    // ignore: avoid_print
    print('decoded: "$decoded"');
    expect(decoded, data);
  });

  test('long Chinese content decodes', () async {
    const data = '这是一个用于测试的比较长的中文内容,用来验证二维码在较长内容下的编解码是否正常,请务必确认。';
    final config = const QrStyleConfig(data: data);
    final bytes = await QrGenerator().exportPng(config);
    final decoded = QrDecoder().decode(bytes);
    // ignore: avoid_print
    print('decoded: "$decoded"');
    expect(decoded, data);
  });

  test('logo embedded decodes', () async {
    const data = 'hello logo';
    // 用 image 包生成一个小 PNG 作为 logo
    final logo = img.Image(width: 24, height: 24);
    for (var y = 0; y < 24; y++) {
      for (var x = 0; x < 24; x++) {
        logo.setPixelRgba(x, y, 230, 30, 30, 255);
      }
    }
    final logoPng = img.encodePng(logo);
    final config = QrStyleConfig(data: data, logoBytes: logoPng);
    final bytes = await QrGenerator().exportPng(config);
    final decoded = QrDecoder().decode(bytes);
    // ignore: avoid_print
    print('decoded: "$decoded"');
    expect(decoded, data);
  });

  test('decoder luminance mapping sanity', () {
    // 构造 2x1 像素图: 黑 + 白
    final image = img.Image(width: 2, height: 1);
    image.setPixelRgba(0, 0, 0, 0, 0, 255);
    image.setPixelRgba(1, 0, 255, 255, 255, 255);
    final bytes = image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr);
    final pixels = bytes.buffer.asInt32List();
    expect(pixels.length, 2);
    for (final p in pixels) {
      final r = (p >> 16) & 0xff;
      final g = (p >> 7) & 0x1fe;
      final b = p & 0xff;
      final lum = (r + g + b) ~/ 4;
      // ignore: avoid_print
      print('pixel=$p r=$r g2=$g b=$b lum=$lum');
    }
  });

  test('large photo-size image downscales and still decodes (Android OOM regression)', () async {
    // 模拟手机相册原图:3000x2400 大图,二维码只占右下角一小块。
    // 回归:修复前全分辨率转亮度图在低内存 Android 设备上直接 OOM 闪退。
    const data = 'big photo qr';
    final config = const QrStyleConfig(data: data);
    final qrBytes = await QrGenerator().exportPng(config, size: 512);
    final qrImage = img.decodeImage(qrBytes)!;
    final canvas = img.Image(width: 3000, height: 2400);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, qrImage, dstX: 2400, dstY: 1800);
    final decoded = QrDecoder().decode(img.encodePng(canvas));
    expect(decoded, data);
  });
}
