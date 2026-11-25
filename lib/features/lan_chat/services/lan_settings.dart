import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LanPaths {
  static late String dataDir;
  static late String downloadDir;
  static late String cacheDir;
  static late String imagesCacheDir;
  static late String transfersCacheDir;
  static late String screenshotsDir;

  static String get settingsFile => p.join(dataDir, 'lan_chat.json');
  static String get tcpTransfersFile =>
      p.join(dataDir, 'lan_transfers_tcp.json');
  static String get httpTransfersFile =>
      p.join(dataDir, 'lan_transfers_http.json');

  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    final support = await getApplicationSupportDirectory();
    dataDir = p.join(support.path, 'zebra');
    await Directory(dataDir).create(recursive: true);

    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } catch (_) {}
    downloads ??= await getApplicationDocumentsDirectory();
    downloadDir = p.join(downloads.path, 'Zebra');
    cacheDir = p.join(dataDir, 'lan_cache');
    imagesCacheDir = p.join(cacheDir, 'images');
    transfersCacheDir = p.join(cacheDir, 'transfers');
    screenshotsDir = p.join(downloadDir, 'Screenshots');
    await Directory(downloadDir).create(recursive: true);
    await Directory(imagesCacheDir).create(recursive: true);
    await Directory(transfersCacheDir).create(recursive: true);
    _inited = true;
  }
}

class LanSettings {
  bool discovery;
  int discoveryPort;
  int port;
  int transferPort;
  int sharePort;
  String downloadDir;
  String shareDir;
  String uploadDir;
  bool shareOnStart;
  bool autoDownloadImages;
  bool notifications;
  bool notifyPreview;
  String language;

  LanSettings({
    this.discovery = true,
    this.discoveryPort = 42223,
    this.port = 42224,
    this.transferPort = 42225,
    this.sharePort = 42230,
    this.downloadDir = '',
    this.shareDir = '',
    this.uploadDir = '',
    this.shareOnStart = false,
    this.autoDownloadImages = true,
    this.notifications = true,
    this.notifyPreview = true,
    this.language = '',
  });

  Map<String, dynamic> toJson() => {
    'discovery': discovery,
    'discoveryPort': discoveryPort,
    'port': port,
    'transferPort': transferPort,
    'sharePort': sharePort,
    'downloadDir': downloadDir,
    'shareDir': shareDir,
    'uploadDir': uploadDir,
    'shareOnStart': shareOnStart,
    'autoDownloadImages': autoDownloadImages,
    'notifications': notifications,
    'notifyPreview': notifyPreview,
    'language': language,
  };

  static LanSettings fromJson(Map<String, dynamic> m) {
    int portOf(Object? v, int fallback) {
      final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return n > 0 && n < 65536 ? n : fallback;
    }

    return LanSettings(
      discovery: m['discovery'] is bool ? m['discovery'] as bool : true,
      discoveryPort: portOf(m['discoveryPort'], 42223),
      port: portOf(m['port'], 42224),
      transferPort: portOf(m['transferPort'], 42225),
      sharePort: portOf(m['sharePort'], 42230),
      downloadDir: '${m['downloadDir'] ?? ''}',
      shareDir: '${m['shareDir'] ?? ''}',
      uploadDir: '${m['uploadDir'] ?? ''}',
      shareOnStart: m['shareOnStart'] == true,
      autoDownloadImages: m['autoDownloadImages'] is bool
          ? m['autoDownloadImages'] as bool
          : true,
      notifications: m['notifications'] is bool
          ? m['notifications'] as bool
          : true,
      notifyPreview: m['notifyPreview'] is bool
          ? m['notifyPreview'] as bool
          : true,
      language: '${m['language'] ?? ''}',
    );
  }

  static Future<LanSettings> load() async {
    await LanPaths.init();
    final defaults = LanSettings(
      downloadDir: LanPaths.downloadDir,
      language: Platform.localeName.toLowerCase().startsWith('zh')
          ? 'zh'
          : 'en',
    );
    final file = File(LanPaths.settingsFile);
    if (!await file.exists()) return defaults;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return defaults;
      final s = fromJson(Map<String, dynamic>.from(raw));
      if (s.downloadDir.isEmpty) s.downloadDir = defaults.downloadDir;
      if (s.language.isEmpty) s.language = defaults.language;
      return s;
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    await LanPaths.init();
    await File(LanPaths.settingsFile).writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
      flush: true,
    );
  }
}

class LanIdentity {
  String id;
  String name;
  String signature;
  String status;

  LanIdentity({
    required this.id,
    required this.name,
    this.signature = '',
    this.status = 'online',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'signature': signature,
    'status': status,
  };

  static LanIdentity? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    final name = '${raw['name'] ?? ''}';
    if (id.isEmpty || name.isEmpty) return null;
    return LanIdentity(
      id: id,
      name: name,
      signature: '${raw['signature'] ?? ''}',
      status: '${raw['status'] ?? 'online'}',
    );
  }
}
