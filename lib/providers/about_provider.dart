import 'package:flutter/foundation.dart';
import '../models/about_info.dart';
import '../services/update_service.dart';

/// 关于页面状态管理
class AboutProvider extends ChangeNotifier {
  AboutInfo _info = AboutInfo.load();
  bool _loaded = false;

  AboutInfo get info => _info;
  bool get loaded => _loaded;

  /// 异步加载版本信息
  Future<void> load() async {
    if (_loaded) return;
    try {
      final version = await UpdateService.getCurrentVersion();
      _info = _info.copyWith(version: version);
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // 加载失败时保留默认空版本
      _loaded = true;
      notifyListeners();
    }
  }

  /// 重置（方便测试或重新加载）
  void reset() {
    _info = AboutInfo.load();
    _loaded = false;
    notifyListeners();
  }
}
