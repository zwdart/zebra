import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../models/qr_style_config.dart';

/// 二维码生成 repository。
///
/// 封装 pretty_qr_code / qr 包:负责把 [QrStyleConfig] 映射为
/// 具体的 QR 图像对象与 PNG 字节。UI 与 provider 不直接接触库类型。
class QrGenerator {
  /// 构建用于预览的 [QrImage]。
  ///
  /// 注意:不应在 build 方法中反复调用(编码有开销),
  /// 建议在配置变化时缓存。
  QrImage buildQrImage(QrStyleConfig config) {
    final qrCode = QrCode.fromData(
      data: config.data,
      errorCorrectLevel: _mapErrorLevel(_effectiveErrorLevel(config)),
    );
    return QrImage(qrCode);
  }

  /// 将二维码渲染为 PNG 字节,用于保存/分享。
  Future<Uint8List> exportPng(
    QrStyleConfig config, {
    int size = 512,
  }) async {
    final qrCode = QrCode.fromData(
      data: config.data,
      errorCorrectLevel: _mapErrorLevel(_effectiveErrorLevel(config)),
    );
    final qrImage = QrImage(qrCode);
    final decoration = buildDecoration(config);
    final byteData = await qrImage.toImageAsBytes(
      size: size,
      format: ui.ImageByteFormat.png,
      decoration: decoration,
    );
    if (byteData == null) {
      throw StateError('QR export failed: toImageAsBytes returned null');
    }
    final bytes = byteData.buffer.asUint8List();
    // 仅在定位角会被样式破坏时重绘,避免干扰 smooth/dots 和标准样式
    // (无条件重绘会引入亚像素误差,叠加 logo 后可能超出纠错能力)。
    if (!_needsFinderRestore(config)) return bytes;
    return _restoreFinderPatterns(bytes, config, qrCode.moduleCount);
  }

  /// 判断该样式是否需要重绘定位角:
  /// pretty_qr_code 的 squares 形状在密度 < 1 或圆角 > 0.1 时,定位角
  /// 会被画成圆点/圆角,zxing 检测不到 1:1:3:1:1 结构;
  /// rounded 形状本质是圆角 0.5 的 squares,同样需要。
  bool _needsFinderRestore(QrStyleConfig config) {
    if (config.shape == QrShapeStyle.rounded) return true;
    return config.shape == QrShapeStyle.squares &&
        (config.density < 1.0 || config.rounding > 0.1);
  }

  /// pretty_qr_code 的 squares 形状在密度 < 1 或圆角较大时,会把定位角
  /// (Finder Pattern)画成圆点/圆角,纯 Dart 的 zxing 检测不到 1:1:3:1:1
  /// 结构导致识别失败(其他 App 用原生引擎可识别)。导出 PNG 时把三个
  /// 定位角重绘为标准实心方块,保证生成的图任何解码器都能识别。
  ///
  /// 布局:画布边长 = size,总模块数 = dimension + 2*quietZone,
  /// 内容区起点 = quietZone * moduleSize。
  Uint8List _restoreFinderPatterns(
    Uint8List png,
    QrStyleConfig config,
    int dimension,
  ) {
    final image = img.decodeImage(png);
    if (image == null) return png;
    final quietZone = config.quietZone;
    final size = image.width;
    // 与 pretty_qr_code 布局一致:quietZone 像素 = value * B/dimension
    // (moduleDimension 不含静区),内容区再整体缩放 (1 - 2*qz/B)。
    final moduleSizeRaw = size / dimension;
    final qz = quietZone * moduleSizeRaw;
    final moduleSize = moduleSizeRaw * (1 - 2 * qz / size);
    final x0 = qz;
    final fg = _toImgColor(config.fgColor);
    final bg = _toImgColor(config.bgColor);
    // 三个定位角的内容区坐标:(0,0)、(dimension-7,0)、(0,dimension-7)
    for (final (fx, fy) in [(0, 0), (dimension - 7, 0), (0, dimension - 7)]) {
      final left = (x0 + fx * moduleSize).round();
      final top = (x0 + fy * moduleSize).round();
      final right = (x0 + (fx + 7) * moduleSize).round();
      final bottom = (x0 + (fy + 7) * moduleSize).round();
      // 外圈 7x7 黑(前景色)
      img.fillRect(image, x1: left, y1: top, x2: right, y2: bottom, color: fg);
      // 1 模块宽白环(背景色)
      final inner = moduleSize.round();
      img.fillRect(
        image,
        x1: left + inner,
        y1: top + inner,
        x2: right - inner,
        y2: bottom - inner,
        color: bg,
      );
      // 中心 3x3 黑(前景色)
      final c3 = (3 * moduleSize).round();
      final cOff = (right - left + 1 - c3) ~/ 2;
      img.fillRect(
        image,
        x1: left + cOff,
        y1: top + cOff,
        x2: left + cOff + c3 - 1,
        y2: top + cOff + c3 - 1,
        color: fg,
      );
    }
    return img.encodePng(image);
  }

  img.Color _toImgColor(Color c) => img.ColorRgba8(
        (c.r * 255).round(),
        (c.g * 255).round(),
        (c.b * 255).round(),
        (c.a * 255).round(),
      );

  /// 根据配置构建绘制装饰(形状/渐变/背景/静区/Logo)。
  PrettyQrDecoration buildDecoration(QrStyleConfig config) {
    return PrettyQrDecoration(
      background: config.bgColor,
      quietZone: PrettyQrQuietZone.modules(config.quietZone.toDouble()),
      image: config.logoBytes != null
          ? PrettyQrDecorationImage(
              image: MemoryImage(config.logoBytes!),
            )
          : null,
      shape: _buildShape(config),
    );
  }

  PrettyQrShape _buildShape(QrStyleConfig config) {
    final color = _buildBrush(config);
    switch (config.shape) {
      case QrShapeStyle.squares:
        return PrettyQrSquaresSymbol(
          color: color,
          density: config.density,
          rounding: config.rounding,
        );
      case QrShapeStyle.smooth:
        return PrettyQrSmoothSymbol(color: color);
      case QrShapeStyle.dots:
        return PrettyQrDotsSymbol(color: color, density: config.density);
      case QrShapeStyle.rounded:
        // PrettyQrRoundedSymbol 已废弃,用带圆角的 squares 替代。
        return PrettyQrSquaresSymbol(color: color, rounding: 0.5);
    }
  }

  /// 前景色:支持渐变 brush。
  Color _buildBrush(QrStyleConfig config) {
    if (!config.useGradient) return config.fgColor;
    final colors = config.gradientColors.isEmpty
        ? <Color>[config.fgColor]
        : config.gradientColors;
    return PrettyQrGradientBrush(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
  }

  int _mapErrorLevel(QrErrorLevel level) {
    switch (level) {
      case QrErrorLevel.low:
        return QrErrorCorrectLevel.L;
      case QrErrorLevel.medium:
        return QrErrorCorrectLevel.M;
      case QrErrorLevel.quartile:
        return QrErrorCorrectLevel.Q;
      case QrErrorLevel.high:
        return QrErrorCorrectLevel.H;
    }
  }

  /// 实际生效的纠错级别。
  ///
  /// logo 会覆盖中心区域的数据模块,低纠错级别(7%/15%)没有足够冗余,
  /// 实测中/短内容 + low + logo 生成的二维码任何解码器都识别不了。
  /// 因此带 logo 时强制最低 Q(25%),保证产物可识别。
  QrErrorLevel _effectiveErrorLevel(QrStyleConfig config) {
    if (config.logoBytes != null &&
        config.errorLevel.index < QrErrorLevel.quartile.index) {
      return QrErrorLevel.quartile;
    }
    return config.errorLevel;
  }
}
