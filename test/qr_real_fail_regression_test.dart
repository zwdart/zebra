import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zebra/features/qr_tool/repositories/qr_decoder.dart';

/// 回归测试:三张历史上识别失败的图片(含手机拍摄 PC 屏幕的照片)。
///
/// 修复前(仅原始分辨率 + 反色重试)三张全部失败:
///   - 手机拍屏幕的 1279x1706 照片:屏幕像素网格形成摩尔纹,
///     破坏 1:1:3:1:1 定位与模块采样;
///   - 白底中心 logo 样式图 / 黑底反色图:直方图二值化阈值被干扰。
/// 修复后(原分辨率失败时按 0.75x/0.5x/0.33x/0.25x 平均插值
/// 降采样重试)应能识别出正确内容。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final decoder = QrDecoder();

  test('手机拍摄 PC 屏幕的二维码可识别', () {
    final bytes = File('test/fixtures/qr_error/粘贴的图像1200.png')
        .readAsBytesSync();
    expect(decoder.decode(bytes), '天马行空1131');
  });

  test('白底中心 logo 样式二维码可识别', () {
    final bytes =
        File('test/fixtures/qr_error/qr_2026-08-03T09-16-54-151249.png')
            .readAsBytesSync();
    expect(decoder.decode(bytes), '逍遥游，庄子。你好吗');
  });

  test('黑底反色样式二维码可识别', () {
    final bytes =
        File('test/fixtures/qr_error/qr_2026-07-31T15-19-22-645137.png')
            .readAsBytesSync();
    expect(decoder.decode(bytes), '提阿天提阿');
  });
}
