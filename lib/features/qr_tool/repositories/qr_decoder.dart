import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// 二维码识别 repository。
///
/// 封装 zxing2:从图片字节中解码二维码内容,全平台可用(纯 Dart)。
class QrDecoder {
  /// 解码图片中的二维码,返回文本内容。
  ///
  /// 图片不是有效二维码时返回 null;图片本身无法解析时抛 [FormatException]。
  String? decode(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('Unsupported or corrupted image');
    }

    // 手机相册原图通常为 1200 万像素以上,全分辨率转亮度图时解码图、
    // convert 拷贝、getBytes 拷贝与亮度源会同时存在多份像素级缓冲区,
    // 峰值内存可达数百 MB,低内存 Android 设备会直接 OOM 崩溃
    // (原生崩溃,Dart 的 try/catch 无法捕获)。二维码识别不需要这么高的
    // 分辨率,先纠正 EXIF 旋转,再等比缩小到 2048 以内,峰值内存降低 4 倍以上。
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

    // 先在原始分辨率下解码(含反色重试)。
    final direct = _tryDecode(image);
    if (direct != null) return direct;

    // 手机拍摄屏幕/纸张的照片会带有像素网格(摩尔纹)、透视与光照不均,
    // 原始分辨率下 GlobalHistogramBinarizer 的全局直方图阈值会被网格干扰,
    // 1:1:3:1:1 定位结构也可能因反光断断续续。用平均插值逐级降采样重试:
    // 平均插值会把细密网格抹成中间灰度,显著提高这类照片的识别率。
    // (实测:手机拍 PC 屏幕 1279x1706 原图失败,0.5x 即可成功。)
    for (final factor in const [0.75, 0.5, 0.33, 0.25]) {
      final w = (image.width * factor).round();
      final h = (image.height * factor).round();
      // 过小无意义:模块会缩到亚像素,任何二值化都无法恢复。
      if (w < 64 || h < 64) continue;
      final scaled = img.copyResize(
        image,
        width: w,
        height: h,
        interpolation: img.Interpolation.average,
      );
      final result = _tryDecode(scaled);
      if (result != null) return result;
    }
    return null;
  }

  /// 在给定分辨率下解码一次,失败返回 null。
  ///
  /// zxing2 的 RGBLuminanceSource 期望 int32 像素为 0xAARRGGBB 布局
  /// (r=(p>>16)&0xff, b=p&0xff)。image 包按 bgra 字节序输出后,
  /// 在小端平台上 asInt32List() 恰好得到 0xAARRGGBB;
  /// 若用 abgr 则通道错位,亮度数据错误,浅色/彩色前景等样式会识别失败。
  /// (HybridBinarizer 在 zxing2 0.2.4 中实测全失败,故用 GlobalHistogramBinarizer。)
  String? _tryDecode(img.Image image) {
    final source = RGBLuminanceSource(
      image.width,
      image.height,
      image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.bgra)
          .buffer
          .asInt32List(),
    );

    try {
      final result =
          QRCodeReader().decode(BinaryBitmap(GlobalHistogramBinarizer(source)));
      return _buildText(result);
    } catch (_) {
      // 反色二维码(白模块/黑背景):翻转亮度后再试一次。
      // 注意:zxing2 的 Detector 对垃圾输入可能抛 ReaderException 之外的
      // 错误(如 ArgumentError "Version is 0"),必须捕获所有异常。
      try {
        final result = QRCodeReader().decode(
          BinaryBitmap(GlobalHistogramBinarizer(InvertedLuminanceSource(source))),
        );
        return _buildText(result);
      } catch (_) {
        // 图片可解析但其中没有可识别的二维码
        return null;
      }
    }
  }

  /// 根据解码结果组装最终文本。
  ///
  /// zxing2 的 `_decodeByteSegment` 会把字节读成有符号 [Int8List],再交给
  /// `allowMalformed` 的 utf8/latin1 codec 解码——非 ASCII 字节(负数)全部
  /// 变成 U+FFFD,中文等内容在 `result.text` 里直接丢失(本工具生成的二维码
  /// 由 qr 包按 UTF-8 编码且不带 ECI 标记,恰好命中该缺陷)。
  ///
  /// 因此这里优先使用 zxing2 在 metadata 中暴露的原始字节段
  /// (`byteSegments`),自行按 UTF-8(严格模式)解码,失败再回退 ISO-8859-1。
  /// 无字节段(纯数字/字母模式)时直接返回 `result.text`。
  String _buildText(Result result) {
    final segments =
        result.resultMetadata[ResultMetadataType.byteSegments] as List<Int8List>?;
    if (segments == null || segments.isEmpty) {
      return result.text;
    }
    final parts = <String>[];
    for (final segment in segments) {
      parts.add(_decodeBytes(segment));
    }
    return parts.length == 1 ? parts.single : parts.join();
  }

  /// 把有符号字节段还原为无符号字节,优先按 UTF-8 严格解码,失败回退 latin1。
  String _decodeBytes(Int8List signedBytes) {
    final bytes = Uint8List(signedBytes.length);
    for (var i = 0; i < signedBytes.length; i++) {
      bytes[i] = signedBytes[i] & 0xff;
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }
}
