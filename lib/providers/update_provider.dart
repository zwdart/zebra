import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/update_service.dart';

enum UpdateState {
  idle,
  checking,
  hasUpdate,
  noUpdate,
  downloading,
  downloadComplete,
  error,
}

class UpdateProvider extends ChangeNotifier {
  UpdateState _state = UpdateState.idle;
  UpdateVersionInfo? _versionInfo;
  DownloadProgress? _progress;
  String? _errorMessage;
  String? _downloadedFilePath;
  bool _forceUpdate = false;

  // API 地址
  String _apiBaseUrl = UpdateService.apiBaseUrl;

  UpdateState get state => _state;
  UpdateVersionInfo? get versionInfo => _versionInfo;
  DownloadProgress? get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get downloadedFilePath => _downloadedFilePath;
  bool get forceUpdate => _forceUpdate;
  String get apiBaseUrl => _apiBaseUrl;

  /// 设置 API 地址
  void setApiBaseUrl(String url) {
    _apiBaseUrl = url;
    UpdateService.apiBaseUrl = url;
    notifyListeners();
  }

  /// 检查更新（手动触发）
  Future<void> checkForUpdate() async {
    _state = UpdateState.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final info = await UpdateService.checkForUpdate(baseUrl: _apiBaseUrl);
      if (info == null) {
        _state = UpdateState.noUpdate;
      } else if (info.hasUpdate) {
        _versionInfo = info;
        _forceUpdate = info.forceUpdate;
        _state = UpdateState.hasUpdate;
      } else {
        _state = UpdateState.noUpdate;
      }
    } catch (e) {
      _state = UpdateState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// 启动时静默检查（不阻塞 UI）
  Future<void> silentCheck() async {
    try {
      final info = await UpdateService.checkForUpdate(baseUrl: _apiBaseUrl);
      if (info != null && info.hasUpdate) {
        _versionInfo = info;
        _forceUpdate = info.forceUpdate;
        _state = UpdateState.hasUpdate;
        notifyListeners();
      }
    } catch (_) {
      // 静默失败，不影响用户体验
    }
  }

  /// 下载更新
  Future<void> downloadUpdate() async {
    if (_versionInfo == null || _versionInfo!.downloadUrl.isEmpty) return;

    _state = UpdateState.downloading;
    _progress = DownloadProgress(received: 0, total: 0);
    notifyListeners();

    final fileName = _getFileName(_versionInfo!.downloadUrl);

    await for (final p in UpdateService.downloadUpdate(
      _versionInfo!.downloadUrl,
      fileName,
    )) {
      _progress = p;
      notifyListeners();

      if (p.isComplete) {
        _state = UpdateState.downloadComplete;
        notifyListeners();
      } else if (p.error != null) {
        _state = UpdateState.error;
        _errorMessage = p.error;
        notifyListeners();
      }
    }
  }

  /// 打开已下载的文件
  Future<void> openDownloadedFile() async {
    if (_downloadedFilePath != null) {
      await UpdateService.openDownloadedFile(_downloadedFilePath!);
    }
  }

  /// 跳转到应用商店
  Future<void> openStore() async {
    await UpdateService.openStore();
  }

  /// 打开外部链接（URL类型更新）
  Future<void> openExternalUrl() async {
    if (_versionInfo != null && _versionInfo!.downloadUrl.isNotEmpty) {
      await UpdateService.openExternalUrl(_versionInfo!.downloadUrl);
    }
  }

  /// 重置状态
  void reset() {
    _state = UpdateState.idle;
    _versionInfo = null;
    _progress = null;
    _errorMessage = null;
    _downloadedFilePath = null;
    _forceUpdate = false;
    notifyListeners();
  }

  String _getFileName(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      return Uri.decodeComponent(pathSegments.last);
    }
    return 'zebra-update-${_versionInfo?.version ?? "unknown"}';
  }
}
