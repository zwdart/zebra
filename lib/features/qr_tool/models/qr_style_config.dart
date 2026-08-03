import 'dart:typed_data';
import 'dart:ui';

/// 二维码容错级别(映射到 qr 包的 QrErrorCorrectLevel)。
enum QrErrorLevel { low, medium, quartile, high }

/// 二维码模块形状。
enum QrShapeStyle { squares, smooth, dots, rounded }

/// 二维码样式配置模型。
///
/// 纯数据模型,不依赖任何第三方库类型,由 repository 层映射到
/// pretty_qr_code / qr 的具体类型,保证 UI 与库解耦。
class QrStyleConfig {
  const QrStyleConfig({
    this.data = '',
    this.errorLevel = QrErrorLevel.medium,
    this.shape = QrShapeStyle.squares,
    this.fgColor = const Color(0xFF000000),
    this.useGradient = false,
    this.gradientColors = const [Color(0xFF000000), Color(0xFF333333)],
    this.bgColor = const Color(0xFFFFFFFF),
    this.quietZone = 4,
    this.density = 1.0,
    this.rounding = 0.0,
    this.logoBytes,
    this.useCustomColor = false,
    this.customColor,
    this.defaultBgColor,
    this.defaultFgColor,
  });

  /// 二维码内容。
  final String data;

  /// 容错级别。
  final QrErrorLevel errorLevel;

  /// 模块形状。
  final QrShapeStyle shape;

  /// 前景(模块)颜色;启用渐变时作为兜底色。
  final Color fgColor;

  /// 是否使用渐变填充。
  final bool useGradient;

  /// 渐变颜色列表。
  final List<Color> gradientColors;

  /// 背景颜色。
  final Color bgColor;

  /// 静区宽度(模块数)。
  final int quietZone;

  /// 模块密度。
  final double density;

  /// 圆角程度(仅 squares 形状生效)。
  final double rounding;

  /// Logo 图片字节。
  final Uint8List? logoBytes;

  /// 是否启用自定义颜色。
  final bool useCustomColor;

  /// 自定义颜色值(当 useCustomColor 为 true 时)。
  final Color? customColor;

  /// 背景色为透明时的默认填充色(当 useCustomColor 为 true 且 bgColor.transparent 时)。
  final Color? defaultBgColor;

  /// 前景色为透明时的默认填充色(当 useCustomColor 为 true 且 fgColor.transparent 时)。
  final Color? defaultFgColor;

  QrStyleConfig copyWith({
    String? data,
    QrErrorLevel? errorLevel,
    QrShapeStyle? shape,
    Color? fgColor,
    bool? useGradient,
    List<Color>? gradientColors,
    Color? bgColor,
    int? quietZone,
    double? density,
    double? rounding,
    Uint8List? logoBytes,
    bool? useCustomColor,
    Color? customColor,
    Color? defaultBgColor,
    Color? defaultFgColor,
  }) {
    return QrStyleConfig(
      data: data ?? this.data,
      errorLevel: errorLevel ?? this.errorLevel,
      shape: shape ?? this.shape,
      fgColor: fgColor ?? this.fgColor,
      useGradient: useGradient ?? this.useGradient,
      gradientColors: gradientColors ?? this.gradientColors,
      bgColor: bgColor ?? this.bgColor,
      quietZone: quietZone ?? this.quietZone,
      density: density ?? this.density,
      rounding: rounding ?? this.rounding,
      logoBytes: logoBytes ?? this.logoBytes,
      useCustomColor: useCustomColor ?? this.useCustomColor,
      customColor: customColor ?? this.customColor,
      defaultBgColor: defaultBgColor ?? this.defaultBgColor,
      defaultFgColor: defaultFgColor ?? this.defaultFgColor,
    );
  }
}
