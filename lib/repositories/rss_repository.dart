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

  List<RssArticle> getArticles(int feedSourceId, {int page = 1, int size = 20}) {
    return RssDatabaseService.getArticles(feedSourceId, page: page, size: size);
  }

  List<RssArticle> getAllArticles({int page = 1, int size = 20}) {
    return RssDatabaseService.getAllArticles(page: page, size: size);
  }

  List<RssArticle> getArticlesByFeedIds(List<int> feedIds, {int page = 1, int size = 20}) {
    return RssDatabaseService.getArticlesByFeedIds(feedIds, page: page, size: size);
  }

  List<RssArticle> getStarredArticles({int page = 1, int size = 20}) {
    return RssDatabaseService.getStarredArticles(page: page, size: size);
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

  /// 同步单个订阅源，返回新增文章数
  Future<int> syncFeedSource(FeedSource source) async {
    final result = await RssApiService.fetchFeed(source.url);

    // Check for errors
    if (result.containsKey('error')) {
      final errorMsg = 'HTTP Error: ${result['error']}';
      if (source.id != null) {
        RssDatabaseService.updateFeedSourceSyncError(source.id!, errorMsg);
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
    }
    return newCount;
  }

  /// 同步所有启用的订阅源
  Future<Map<int, int>> syncAllFeedSources() async {
    final sources = getAllFeedSources().where((s) => s.syncEnabled).toList();
    final results = <int, int>{};
    for (final source in sources) {
      try {
        final count = await syncFeedSource(source);
        results[source.id!] = count;
      } catch (_) {
        results[source.id!] = 0;
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
}
