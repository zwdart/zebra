import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../database/rss_database_service.dart';
import '../models/feed_source.dart';
import '../models/rss_article.dart';
import '../services/rss_api_service.dart';

class RssRepository {
  // ==================== Feed Sources ====================

  List<FeedSource> getAllFeedSources() {
    return RssDatabaseService.getAllFeedSources();
  }

  FeedSource? getFeedSource(int id) {
    return RssDatabaseService.getFeedSource(id);
  }

  FeedSource? getFeedSourceByUrl(String url) {
    return RssDatabaseService.getFeedSourceByUrl(url);
  }

  int addFeedSource(FeedSource source) {
    return RssDatabaseService.insertFeedSource(source);
  }

  void updateFeedSource(FeedSource source) {
    RssDatabaseService.updateFeedSource(source);
  }

  void deleteFeedSource(int id) {
    RssDatabaseService.deleteFeedSource(id);
  }

  void deleteFeedSources(List<int> ids) {
    RssDatabaseService.deleteFeedSources(ids);
  }

  // ==================== Articles ====================

  List<RssArticle> getArticles(int feedSourceId,
      {int page = 1, int size = 20, String? beforeCreatedAt, int? beforeId}) {
    return RssDatabaseService.getArticles(feedSourceId,
        page: page, size: size, beforeCreatedAt: beforeCreatedAt, beforeId: beforeId);
  }

  List<RssArticle> getAllArticles(
      {int page = 1, int size = 20, String? beforeCreatedAt, int? beforeId}) {
    return RssDatabaseService.getAllArticles(
        page: page, size: size, beforeCreatedAt: beforeCreatedAt, beforeId: beforeId);
  }

  List<RssArticle> getArticlesByFeedIds(List<int> feedIds,
      {int page = 1, int size = 20, String? beforeCreatedAt, int? beforeId}) {
    return RssDatabaseService.getArticlesByFeedIds(feedIds,
        page: page, size: size, beforeCreatedAt: beforeCreatedAt, beforeId: beforeId);
  }

  List<RssArticle> getStarredArticles(
      {int page = 1, int size = 20, String? beforeCreatedAt, int? beforeId}) {
    return RssDatabaseService.getStarredArticles(
        page: page, size: size, beforeCreatedAt: beforeCreatedAt, beforeId: beforeId);
  }

  /// FTS5 全文搜索
  List<RssArticle> searchArticles(String keyword,
      {int page = 1, int size = 20, String? beforeCreatedAt, int? beforeId}) {
    return RssDatabaseService.searchArticles(keyword,
        page: page, size: size, beforeCreatedAt: beforeCreatedAt, beforeId: beforeId);
  }

  RssArticle? getArticle(int id) {
    return RssDatabaseService.getArticle(id);
  }

  int getArticleCount(int feedSourceId) {
    return RssDatabaseService.getArticleCount(feedSourceId);
  }

  int getUnreadCount(int feedSourceId) {
    return RssDatabaseService.getUnreadCount(feedSourceId);
  }

  int getTotalUnreadCount() {
    return RssDatabaseService.getTotalUnreadCount();
  }

  void markAsRead(int articleId) {
    RssDatabaseService.markAsRead(articleId);
  }

  void markAsUnread(int articleId) {
    RssDatabaseService.markAsUnread(articleId);
  }

  void markAllAsRead(int feedSourceId) {
    RssDatabaseService.markAllAsRead(feedSourceId);
  }

  void toggleStar(int articleId) {
    RssDatabaseService.toggleStar(articleId);
  }

  void deleteArticle(int articleId) {
    RssDatabaseService.deleteArticle(articleId);
  }

  void clearFeedArticles(int feedSourceId) {
    RssDatabaseService.clearFeedArticles(feedSourceId);
  }

  void clearHistory({int? feedSourceId, DateTime? before}) {
    RssDatabaseService.clearHistory(feedSourceId: feedSourceId, before: before);
  }

  // ==================== Sync / Parse ====================

  /// 连续失败计数（内存态，重启即重置，允许重启后重新尝试）
  final Map<int, int> _failureCounts = {};
  int _syncCycle = 0;

  /// 插入文章到本地库(INSERT OR IGNORE 按 (feed_source_id, guid) 唯一索引去重)
  /// 返回 true 表示真正新增,false 表示已存在被忽略
  bool insertArticle(RssArticle article) {
    final existing = RssDatabaseService.getArticleByGuid(article.feedSourceId, article.guid);
    if (existing != null) return false;
    RssDatabaseService.insertArticle(article);
    return true;
  }

  /// 同步单个订阅源，返回新增文章数
  Future<int> syncFeedSource(FeedSource source) async {
    final result = await RssApiService.fetchFeed(source.url, ifModifiedSince: source.lastSyncedAt);

    // 304 Not Modified：源内容未变化，只更新时间戳
    if (result.containsKey('notModified')) {
      if (source.id != null) {
        RssDatabaseService.updateFeedSourceSyncTime(source.id!);
        _failureCounts[source.id!] = 0;
      }
      return 0;
    }

    // Check for errors
    if (result.containsKey('error')) {
      final errorMsg = 'HTTP Error: ${result['error']}';
      if (source.id != null) {
        RssDatabaseService.updateFeedSourceSyncError(source.id!, errorMsg);
        _failureCounts[source.id!] = (_failureCounts[source.id!] ?? 0) + 1;
      }
      return 0;
    }

    final body = result['body'] as String;
    final articles = _parseFeed(body, source.feedType, feedSourceId: source.id ?? 0).reversed.toList();

    int newCount = 0;
    for (final article in articles) {
      final existing = RssDatabaseService.getArticleByGuid(source.id ?? 0, article.guid);
      if (existing == null) {
        RssDatabaseService.insertArticle(article);
        newCount++;
      }
    }

    if (source.id != null) {
      RssDatabaseService.updateFeedSourceSyncTime(source.id!);
      _failureCounts[source.id!] = 0;
    }
    return newCount;
  }

  /// 同步所有启用的订阅源（受限并发，单批 4 个）
  /// 连续失败 >= 3 次的源降频：每第 3 个同步周期才重试一次，避免反复拖慢整体。
  Future<Map<int, int>> syncAllFeedSources({
    void Function(int done, int total, String? title)? onProgress,
  }) async {
    _syncCycle++;
    final all = getAllFeedSources().where((s) => s.syncEnabled).toList();
    final sources = all.where((s) {
      if (s.id == null) return true;
      final fails = _failureCounts[s.id!] ?? 0;
      return fails < 3 || _syncCycle % 3 == 0;
    }).toList();

    final results = <int, int>{};
    const batchSize = 4;
    var done = 0;

    for (var i = 0; i < sources.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, sources.length);
      final batch = sources.sublist(i, end);
      final batchResults = await Future.wait(batch.map((source) async {
        final count = await syncFeedSource(source);
        done++;
        onProgress?.call(done, sources.length, source.title);
        return (id: source.id, count: count);
      }));
      for (final r in batchResults) {
        if (r.id != null) results[r.id!] = r.count;
      }
    }
    return results;
  }

  /// 从服务器收藏订阅源到本地
  Future<bool> bookmarkFromServer(FeedSource serverSource) async {
    final existing = getFeedSourceByUrl(serverSource.url);
    if (existing != null) return false;

    final local = FeedSource(
      title: serverSource.title,
      url: serverSource.url,
      siteUrl: serverSource.siteUrl,
      feedType: serverSource.feedType,
      category: serverSource.category,
      source: 'server',
    );
    addFeedSource(local);
    return true;
  }

  // ==================== XML Parsing ====================

  List<RssArticle> _parseFeed(String xmlString, String feedType, {int feedSourceId = 0}) {
    try {
      final document = XmlDocument.parse(xmlString);
      final root = document.rootElement;

      // Auto-detect format if not specified
      final actualType = feedType.isEmpty ? _detectFeedType(root) : feedType;

      switch (actualType) {
        case 'rss1':
          return _parseRss1(document, feedSourceId: feedSourceId);
        case 'atom':
          return _parseAtom(document, feedSourceId: feedSourceId);
        case 'rss2':
        default:
          return _parseRss2(document, feedSourceId: feedSourceId);
      }
    } catch (_) {
      return [];
    }
  }

  String _detectFeedType(XmlElement root) {
    final name = root.name.local;
    if (name == 'feed') return 'atom';
    if (name == 'RDF' || root.name.prefix == 'rdf') return 'rss1';
    return 'rss2';
  }

  List<RssArticle> _parseRss2(XmlDocument document, {int feedSourceId = 0}) {
    final articles = <RssArticle>[];
    final items = document.findAllElements('item');
    for (final item in items) {
      articles.add(RssArticle(
        feedSourceId: feedSourceId,
        guid: _getText(item, 'guid') ?? _getText(item, 'link') ?? '',
        title: _getText(item, 'title') ?? '',
        link: _getText(item, 'link') ?? '',
        author: _getText(item, 'author') ?? _getText(item, 'dc:creator') ?? '',
        summary: _getText(item, 'description') ?? '',
        content: _getText(item, 'content:encoded') ?? _getText(item, 'description') ?? '',
        publishedAt: _getText(item, 'pubDate') ?? _getText(item, 'dc:date') ?? '',
      ));
    }
    return articles;
  }

  List<RssArticle> _parseRss1(XmlDocument document, {int feedSourceId = 0}) {
    final articles = <RssArticle>[];
    final items = document.findAllElements('item');
    for (final item in items) {
      final about = item.getAttribute('rdf:about') ?? '';
      articles.add(RssArticle(
        feedSourceId: feedSourceId,
        guid: about.isNotEmpty ? about : (_getText(item, 'guid') ?? ''),
        title: _getText(item, 'title') ?? '',
        link: _getText(item, 'link') ?? '',
        author: _getText(item, 'dc:creator') ?? '',
        summary: _getText(item, 'description') ?? '',
        content: _getText(item, 'content:encoded') ?? _getText(item, 'description') ?? '',
        publishedAt: _getText(item, 'dc:date') ?? '',
      ));
    }
    return articles;
  }

  List<RssArticle> _parseAtom(XmlDocument document, {int feedSourceId = 0}) {
    final articles = <RssArticle>[];
    final entries = document.findAllElements('entry');
    for (final entry in entries) {
      final id = _getText(entry, 'id') ?? '';
      final link = _getAtomLink(entry) ?? '';
      articles.add(RssArticle(
        feedSourceId: feedSourceId,
        guid: id,
        title: _getText(entry, 'title') ?? '',
        link: link,
        author: _getText(entry, 'author/name') ?? _getText(entry, 'author') ?? '',
        summary: _getText(entry, 'summary') ?? '',
        content: _getText(entry, 'content') ?? _getText(entry, 'summary') ?? '',
        publishedAt: _getText(entry, 'published') ?? _getText(entry, 'updated') ?? '',
      ));
    }
    return articles;
  }

  String? _getText(XmlElement parent, String path) {
    try {
      final element = parent.findElements(path).firstOrNull;
      if (element == null) return null;
      final text = element.innerText.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  String? _getAtomLink(XmlElement entry) {
    // Atom links can be in <link href="..."/> or <link rel="alternate" href="..."/>
    for (final link in entry.findElements('link')) {
      final rel = link.getAttribute('rel') ?? 'alternate';
      if (rel == 'alternate') {
        return link.getAttribute('href');
      }
    }
    // Fallback: first link
    final firstLink = entry.findElements('link').firstOrNull;
    return firstLink?.getAttribute('href');
  }

  // ==================== Import / Export ====================

  /// 导出指定订阅源列表为 CSV
  String exportToCsvForSources(List<FeedSource> sources) => exportToCsv(sources);

  /// 导出指定订阅源列表为 OPML
  String exportToOpmlForSources(List<FeedSource> sources) => exportToOpml(sources);

  /// 导出订阅源为 CSV
  String exportToCsv(List<FeedSource> sources) {
    final buffer = StringBuffer();
    buffer.writeln('title,url,site_url,feed_type,category');
    for (final s in sources) {
      buffer.writeln('"${_csvEscape(s.title)}","${_csvEscape(s.url)}","${_csvEscape(s.siteUrl)}","${_csvEscape(s.feedType)}","${_csvEscape(s.category)}"');
    }
    return buffer.toString();
  }

  /// 从 CSV 导入订阅源
  List<FeedSource> importFromCsv(String csv) {
    final sources = <FeedSource>[];
    final lines = csv.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return sources;

    // Skip header
    for (var i = 1; i < lines.length; i++) {
      final fields = _parseCsvLine(lines[i]);
      if (fields.length >= 2 && fields[1].isNotEmpty) {
        sources.add(FeedSource(
          title: fields[0],
          url: fields[1],
          siteUrl: fields.length > 2 ? fields[2] : '',
          feedType: fields.length > 3 ? fields[3] : 'rss2',
          category: fields.length > 4 ? fields[4] : '',
          source: 'local',
        ));
      }
    }
    return sources;
  }

  /// 导出订阅源为 OPML
  String exportToOpml(List<FeedSource> sources) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<opml version="2.0">');
    buffer.writeln('<head><title>Zebra RSS Subscriptions</title></head>');
    buffer.writeln('<body>');
    for (final s in sources) {
      buffer.writeln('  <outline text="${_xmlEscape(s.title)}" title="${_xmlEscape(s.title)}" type="rss" xmlUrl="${_xmlEscape(s.url)}" htmlUrl="${_xmlEscape(s.siteUrl)}"/>');
    }
    buffer.writeln('</body>');
    buffer.writeln('</opml>');
    return buffer.toString();
  }

  /// 从 OPML 导入订阅源
  List<FeedSource> importFromOpml(String opml) {
    final sources = <FeedSource>[];
    try {
      final document = XmlDocument.parse(opml);
      final outlines = document.findAllElements('outline');
      for (final outline in outlines) {
        final xmlUrl = outline.getAttribute('xmlUrl') ?? outline.getAttribute('xmlurl') ?? '';
        if (xmlUrl.isEmpty) continue;
        final title = outline.getAttribute('title') ?? outline.getAttribute('text') ?? '';
        final htmlUrl = outline.getAttribute('htmlUrl') ?? outline.getAttribute('htmlurl') ?? '';
        sources.add(FeedSource(
          title: title.isNotEmpty ? title : xmlUrl,
          url: xmlUrl,
          siteUrl: htmlUrl,
          feedType: _detectFeedTypeFromUrl(xmlUrl),
          source: 'local',
        ));
      }
    } catch (_) {}
    return sources;
  }

  String _detectFeedTypeFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('atom')) return 'atom';
    return 'rss2';
  }

  String _csvEscape(String value) {
    return value.replaceAll('"', '""');
  }

  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    var current = '';
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            current += '"';
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          current += c;
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          fields.add(current);
          current = '';
        } else {
          current += c;
        }
      }
    }
    fields.add(current);
    return fields;
  }

  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // ==================== Folders ====================

  List<Map<String, dynamic>> getAllFolders() {
    return RssDatabaseService.getAllFolders();
  }

  Map<String, dynamic>? getFolder(int id) {
    return RssDatabaseService.getFolder(id);
  }

  int createFolder(String name, String description) {
    return RssDatabaseService.createFolder(name, description);
  }

  void updateFolder(int id, String name, String description) {
    RssDatabaseService.updateFolder(id, name, description);
  }

  void deleteFolder(int id) {
    RssDatabaseService.deleteFolder(id);
  }

  List<FeedSource> getFolderSources(int folderId) {
    return RssDatabaseService.getFolderSources(folderId);
  }

  void addSourceToFolder(int folderId, int sourceId) {
    RssDatabaseService.addSourceToFolder(folderId, sourceId);
  }

  void removeSourceFromFolder(int folderId, int sourceId) {
    RssDatabaseService.removeSourceFromFolder(folderId, sourceId);
  }

  bool isSourceInFolder(int folderId, int sourceId) {
    return RssDatabaseService.isSourceInFolder(folderId, sourceId);
  }

  List<Map<String, dynamic>> getSourceFolderReferences(int sourceId) {
    return RssDatabaseService.getSourceFolderReferences(sourceId);
  }

  // ==================== Auto Backup ====================

  static const _prefAutoBackupEnabled = 'rss_auto_backup_enabled';
  static const _prefLastBackupAt = 'rss_last_backup_at';

  /// 自动备份开关状态
  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoBackupEnabled) ?? false;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoBackupEnabled, enabled);
  }

  /// 检查并按需执行定时备份（每 7 天一次，保留最近 3 份）
  Future<bool> maybeAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_prefAutoBackupEnabled) ?? false)) return false;

    final last = prefs.getString(_prefLastBackupAt);
    if (last != null) {
      final lastTime = DateTime.tryParse(last);
      if (lastTime != null && DateTime.now().difference(lastTime).inDays < 7) {
        return false;
      }
    }

    final ok = await writeBackupNow();
    if (ok) {
      await prefs.setString(_prefLastBackupAt, DateTime.now().toIso8601String());
    }
    return ok;
  }

  /// 立即执行一次 OPML 备份到 ApplicationSupportDirectory/zebra/backups/
  Future<bool> writeBackupNow() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final backupDir = Directory(p.join(appDir.path, 'zebra', 'backups'));
      if (!backupDir.existsSync()) backupDir.createSync(recursive: true);

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(backupDir.path, 'rss_backup_$stamp.opml'));
      await file.writeAsString(exportToOpml(getAllFeedSources()));

      // 保留最近 3 份
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.opml'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(3)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
