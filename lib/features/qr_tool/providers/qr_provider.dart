import 'package:flutter/foundation.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../models/qr_style_config.dart';
import '../repositories/qr_decoder.dart';
import '../repositories/qr_generator.dart';

/// 二维码工具的状态管理。
///
/// 持有样式配置与识别结果,生成/识别逻辑委托给 repository,
/// UI 只通过本 Provider 读写状态。
class QrProvider extends ChangeNotifier {
  QrProvider({QrGenerator? generator})
      : _generator = generator ?? QrGenerator();

  final QrGenerator _generator;

  QrStyleConfig _config = const QrStyleConfig();
  QrStyleConfig get config => _config;

  /// 最近一次识别出的文本,未识别或识别失败为 null。
  String? _lastDecoded;
  String? get lastDecoded => _lastDecoded;

  /// 最近一次识别成功的时间,未识别成功为 null。
  DateTime? _lastDecodedAt;
  DateTime? get lastDecodedAt => _lastDecodedAt;

  bool _isDecoding = false;
  bool get isDecoding => _isDecoding;

  /// 更新配置(整体替换),触发预览刷新。
  void updateConfig(QrStyleConfig config) {
    _config = config;
    notifyListeners();
  }

  /// 更新配置的单个字段。
  void updateConfigField(QrStyleConfig Function(QrStyleConfig) update) {
    _config = update(_config);
    notifyListeners();
  }

  /// 构建用于预览的 [QrImage](基于当前配置)。
  QrImage buildPreviewImage() => _generator.buildQrImage(_config);

  /// 基于当前配置构建绘制装饰(形状/渐变/背景/静区/Logo)。
  PrettyQrDecoration buildDecoration() => _generator.buildDecoration(_config);

  /// 将当前配置导出为 PNG 字节。
  Future<Uint8List> exportPng({int size = 512}) {
    return _generator.exportPng(_config, size: size);
  }

  /// 识别图片中的二维码,结果存入 [lastDecoded]。
  Future<String?> decodeImage(Uint8List bytes) async {
    _isDecoding = true;
    _lastDecoded = null;
    _lastDecodedAt = null;
    notifyListeners();
    try {
      final text = await _decodeInBackground(bytes);
      _lastDecoded = text;
      // 仅在识别成功时记录时间,失败保持 null。
      if (text != null) {
        _lastDecodedAt = DateTime.now();
      }
      return text;
    } finally {
      _isDecoding = false;
      notifyListeners();
    }
  }

  Future<String?> _decodeInBackground(Uint8List bytes) {
    // 解码是 CPU 密集型操作,放到后台 isolate 避免卡 UI。
    return compute(_decodeTask, bytes);
  }

  static String? _decodeTask(Uint8List bytes) {
    return QrDecoder().decode(bytes);
  }

  /// 清除识别结果。
  void clearDecoded() {
    _lastDecoded = null;
    notifyListeners();
  }
}
