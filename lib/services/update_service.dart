import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 版本信息
class UpdateVersionInfo {
  final String version;
  final int versionCode;
  final String type; // 'file' 或 'url'
  final String downloadUrl;
  final bool forceUpdate;
  final String changelog;
  final int fileSize;
  final String fileHash;
  final String releaseDate;
  final String? minSupportedVersion;
  final String? fileName;

  UpdateVersionInfo({
    required this.version,
    required this.versionCode,
    required this.type,
    required this.downloadUrl,
    required this.forceUpdate,
    required this.changelog,
    required this.fileSize,
    required this.fileHash,
    required this.releaseDate,
    this.minSupportedVersion,
    this.fileName,
  });

  bool get hasUpdate => downloadUrl.isNotEmpty && versionCode > 0;
  bool get isUrlType => type == 'url';

  factory UpdateVersionInfo.empty() => UpdateVersionInfo(
    version: '',
    versionCode: 0,
    type: 'file',
    downloadUrl: '',
    forceUpdate: false,
    changelog: '',
    fileSize: 0,
    fileHash: '',
    releaseDate: '',
  );

  factory UpdateVersionInfo.fromJson(Map<String, dynamic> json) {
    return UpdateVersionInfo(
      version: json['version'] ?? '',
      versionCode: json['version_code'] ?? 0,
      type: json['type'] ?? 'file',
      downloadUrl: json['download_url'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      changelog: json['changelog'] ?? '',
      fileSize: json['file_size'] ?? 0,
      fileHash: json['file_hash'] ?? '',
      releaseDate: json['release_date'] ?? '',
      minSupportedVersion: json['min_supported_version'],
      fileName: json['file_name'],
    );
  }
}

/// 更新下载进度
class DownloadProgress {
  final int received;
  final int total;
  final bool isComplete;
  final String? error;

  DownloadProgress({
    required this.received,
    required this.total,
    this.isComplete = false,
    this.error,
  });

  double get percent => total > 0 ? received / total : 0;
}

/// 版本更新服务
class UpdateService {
  static const String _defaultApiBaseUrl = 'https://zebra.dart.xin';
  static const String _prefKeyApiBaseUrl = 'api_base_url';

  /// API 基础地址
  static String apiBaseUrl = _defaultApiBaseUrl;

  /// 初始化：从 SharedPreferences 加载保存的 API 地址
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    apiBaseUrl = prefs.getString(_prefKeyApiBaseUrl) ?? _defaultApiBaseUrl;
  }

  /// 设置并持久化 API 基础地址
  static Future<void> setApiBaseUrl(String url) async {
    apiBaseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyApiBaseUrl, url);
  }

  /// 重置为默认 API 地址
  static Future<void> resetApiBaseUrl() async {
    apiBaseUrl = _defaultApiBaseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyApiBaseUrl);
  }

  /// 获取当前平台标识
  static String get _platform {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// 获取当前应用版本号
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 获取当前应用版本序列号（build number）
  static Future<int> getCurrentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.parse(info.buildNumber);
  }

  /// 检查是否有新版本
  /// 返回 null 表示已是最新或检查失败
  static Future<UpdateVersionInfo?> checkForUpdate({String? baseUrl}) async {
    final url = baseUrl ?? apiBaseUrl;
    final currentVersion = await getCurrentVersion();
    final currentVersionCode = await getCurrentVersionCode();

    try {
      final uri = Uri.parse('$url/api/version');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'current_version': currentVersion,
          'version_code': currentVersionCode,
          'platform': _platform,
        }),
      ).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = Map<String, dynamic>.from(
          // ignore: avoid_dynamic_calls
          (jsonDecode(response.body) as dynamic) ?? {},
        );
        return UpdateVersionInfo.fromJson(json);
      }
      return null;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// 下载更新文件
  static Stream<DownloadProgress> downloadUpdate(
    String downloadUrl,
    String fileName,
  ) async* {
    try {
      final uri = Uri.parse(downloadUrl);
      final request = http.Request('GET', uri);
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        yield DownloadProgress(
          received: 0,
          total: 0,
          error: 'HTTP ${response.statusCode}',
        );
        return;
      }

      final contentLength = response.contentLength ?? 0;
      int received = 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        yield DownloadProgress(
          received: received,
          total: contentLength,
        );
      }

      // 保存文件
      final dir = await _getDownloadDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      yield DownloadProgress(
        received: received,
        total: contentLength,
        isComplete: true,
      );
    } catch (e) {
      yield DownloadProgress(
        received: 0,
        total: 0,
        error: e.toString(),
      );
    }
  }

  /// 获取下载目录
  static Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    // 桌面平台：使用用户 Downloads 目录
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final downloads = Directory('$home/Downloads');
    if (await downloads.exists()) return downloads;
    return await getApplicationDocumentsDirectory();
  }

  /// 获取下载文件的完整路径
  static Future<String> getDownloadPath(String fileName) async {
    final dir = await _getDownloadDirectory();
    return '${dir.path}/$fileName';
  }

  /// 打开包含文件的文件夹
  static Future<void> openContainingFolder(String filePath) async {
    final dir = Directory(filePath).parent.path;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
      }
    } catch (e) {
      debugPrint('Failed to open folder: $e');
    }
  }

  /// 打开下载的文件（桌面平台）或启动安装
  static Future<void> openDownloadedFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    if (Platform.isWindows) {
      // Windows: 直接运行安装程序
      await Process.run(filePath, []);
    } else if (Platform.isLinux) {
      // Linux: 赋予执行权限并运行
      await Process.run('chmod', ['+x', filePath]);
      await Process.run(filePath, []);
    } else if (Platform.isMacOS) {
      // macOS: 打开文件
      await Process.run('open', [filePath]);
    } else if (Platform.isAndroid || Platform.isIOS) {
      // 移动端：打开 URL（跳转到应用商店或浏览器）
      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  /// 打开外部链接（URL 类型更新）
  static Future<void> openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 跳转到应用商店（移动端）
  static Future<void> openStore() async {
    String url;
    if (Platform.isAndroid) {
      url = 'market://details?id=xin.dart.zebra';
    } else if (Platform.isIOS) {
      url = 'itms-apps://apps.apple.com/app/id123456789';
    } else {
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
