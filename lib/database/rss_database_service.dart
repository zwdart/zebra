import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import '../models/feed_source.dart';
import '../models/rss_article.dart';

/// 数据库加密密钥 — release 模式使用，与主数据库保持一致。
/// TODO: 可改为从系统密钥链（Keychain / KeyStore）读取以增强安全性。
const _dbEncryptionKey = 'zebra_db_key_2016';

class RssDatabaseService {
  static Database? _db;
  static String? _dbPath;

  static String get dbPath => _dbPath ?? '';

  static Future<void> init() async {
    if (_db != null) return;

    final appDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(appDir.path, 'zebra'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }

    _dbPath = p.join(dbDir.path, 'zebra_rss.db');
    _db = sqlite3.open(_dbPath!);

    // Release 构建启用数据库加密，调试模式不加密方便开发
    if (kReleaseMode) {
      _db!.execute("PRAGMA key = '$_dbEncryptionKey'");
    }

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS feed_sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        url TEXT NOT NULL,
        site_url TEXT DEFAULT '',
        feed_type TEXT NOT NULL DEFAULT 'rss2',
        icon_url TEXT DEFAULT '',
        category TEXT DEFAULT '',
        last_synced_at TEXT DEFAULT NULL,
        sync_enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'local',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    _db!.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_feed_sources_url ON feed_sources(url)');
    _db!.execute('CREATE INDEX IF NOT EXISTS idx_feed_sources_synced ON feed_sources(last_synced_at)');

    // Migration: add last_sync_error column if missing
    final columns = _db!.select("PRAGMA table_info(feed_sources)").map((r) => r['name'] as String).toList();
    if (!columns.contains('last_sync_error')) {
      _db!.execute("ALTER TABLE feed_sources ADD COLUMN last_sync_error TEXT DEFAULT NULL");
    }

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_source_id INTEGER NOT NULL,
        guid TEXT DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        link TEXT NOT NULL DEFAULT '',
        author TEXT DEFAULT '',
        summary TEXT DEFAULT '',
        content TEXT DEFAULT '',
        published_at TEXT DEFAULT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        is_starred INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    _db!.execute('CREATE INDEX IF NOT EXISTS idx_articles_feed ON articles(feed_source_id)');
    _db!.execute('CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(published_at DESC)');
    _db!.execute('CREATE INDEX IF NOT EXISTS idx_articles_read ON articles(is_read)');
    _db!.execute('CREATE INDEX IF NOT EXISTS idx_articles_starred ON articles(is_starred)');
    _db!.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_articles_feed_guid ON articles(feed_source_id, guid)');

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS rss_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS rss_folder_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER NOT NULL,
        source_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (folder_id) REFERENCES rss_folders(id) ON DELETE CASCADE,
        FOREIGN KEY (source_id) REFERENCES feed_sources(id) ON DELETE CASCADE,
        UNIQUE(folder_id, source_id)
      )
    ''');
    _db!.execute('CREATE INDEX IF NOT EXISTS idx_local_folder_items_folder ON rss_folder_items(folder_id)');
    _db!.execute('CREATE INDEX IF NOT EXISTS idx_local_folder_items_source ON rss_folder_items(source_id)');

    // Auto-seed default RSS sources if database is empty
    _seedDefaultSources();
  }

  /// Seed 5 default RSS sources and create "默认" folder with first 3 sources
  static void _seedDefaultSources() {
    final sourceCount = _db!
        .select("SELECT COUNT(*) as cnt FROM feed_sources")
        .first['cnt'] as int;
    final folderCount = _db!
        .select("SELECT COUNT(*) as cnt FROM rss_folders")
        .first['cnt'] as int;

    if (sourceCount > 0 && folderCount > 0) return;

    final defaults = [
      {'title': '别的', 'url': 'https://www.biede.com/feed/'},
      {'title': '虎嗅网', 'url': 'https://rss.huxiu.com'},
      {'title': 'Nature', 'url': 'https://www.nature.com/nature.rss'},
      {'title': '美团技术', 'url': 'https://tech.meituan.com/rss.xml'},
      {'title': '钛媒体', 'url': 'https://www.tmtpost.com/feed'},
    ];

    // Insert default sources
    final insertSource = _db!.prepare('''
      INSERT OR IGNORE INTO feed_sources (title, url, site_url, feed_type, icon_url, category, sync_enabled, sort_order, source, created_at, updated_at)
      VALUES (?, ?, '', 'rss2', '', '', 1, 0, 'default', datetime('now'), datetime('now'))
    ''');

    final List<int> sourceIds = [];
    for (final d in defaults) {
      try {
        insertSource.execute([d['title'], d['url']]);
        final idResult = _db!.select(
          'SELECT id FROM feed_sources WHERE url = ?',
          [d['url']],
        );
        if (idResult.isNotEmpty) {
          sourceIds.add(idResult.first['id'] as int);
        }
      } catch (_) {}
    }
    insertSource.close();

    // Create "默认" folder
    final stmt = _db!.prepare(
      "INSERT INTO rss_folders (name, description, created_at, updated_at) VALUES ('默认', '默认收藏夹', datetime('now'), datetime('now'))"
    );
    stmt.execute([]);
    final folderId = _db!.lastInsertRowId;
    stmt.close();

    // Add first 3 sources to "默认" folder
    final addFolderItem = _db!.prepare(
      'INSERT OR IGNORE INTO rss_folder_items (folder_id, source_id, created_at) VALUES (?, ?, datetime(\'now\'))'
    );
    for (final id in sourceIds.take(3)) {
      addFolderItem.execute([folderId, id]);
    }
    addFolderItem.close();
  }

  // ==================== Feed Sources ====================

  static List<FeedSource> getAllFeedSources() {
    final results = _db!.select('SELECT * FROM feed_sources ORDER BY sort_order ASC, created_at DESC');
    return results.map((row) => FeedSource.fromMap(row)).toList();
  }

  static FeedSource? getFeedSource(int id) {
    final results = _db!.select('SELECT * FROM feed_sources WHERE id = ?', [id]);
    if (results.isEmpty) return null;
    return FeedSource.fromMap(results.first);
  }

  static FeedSource? getFeedSourceByUrl(String url) {
    final results = _db!.select('SELECT * FROM feed_sources WHERE url = ?', [url]);
    if (results.isEmpty) return null;
    return FeedSource.fromMap(results.first);
  }

  static int insertFeedSource(FeedSource source) {
    final stmt = _db!.prepare('''
      INSERT INTO feed_sources (title, url, site_url, feed_type, icon_url, category, sync_enabled, sort_order, source, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
    ''');
    stmt.execute([
      source.title,
      source.url,
      source.siteUrl,
      source.feedType,
      source.iconUrl,
      source.category,
      source.syncEnabled ? 1 : 0,
      source.sortOrder,
      source.source,
    ]);
    final lastId = _db!.lastInsertRowId;
    stmt.close();
    return lastId;
  }

  static void updateFeedSource(FeedSource source) {
    final stmt = _db!.prepare('''
      UPDATE feed_sources
      SET title = ?, url = ?, site_url = ?, feed_type = ?, icon_url = ?,
          category = ?, last_synced_at = ?, sync_enabled = ?, sort_order = ?,
          source = ?, updated_at = datetime('now')
      WHERE id = ?
    ''');
    stmt.execute([
      source.title,
      source.url,
      source.siteUrl,
      source.feedType,
      source.iconUrl,
      source.category,
      source.lastSyncedAt,
      source.syncEnabled ? 1 : 0,
      source.sortOrder,
      source.source,
      source.id,
    ]);
    stmt.close();
  }

  static void updateFeedSourceSyncTime(int id) {
    final stmt = _db!.prepare('''
      UPDATE feed_sources SET last_synced_at = datetime('now'), last_sync_error = NULL, updated_at = datetime('now') WHERE id = ?
    ''');
    stmt.execute([id]);
    stmt.close();
  }

  static void updateFeedSourceSyncError(int id, String error) {
    final stmt = _db!.prepare('''
      UPDATE feed_sources SET last_sync_error = ?, updated_at = datetime('now') WHERE id = ?
    ''');
    stmt.execute([error, id]);
    stmt.close();
  }

  static void deleteFeedSource(int id) {
    final stmt1 = _db!.prepare('DELETE FROM articles WHERE feed_source_id = ?');
    stmt1.execute([id]);
    stmt1.close();
    final stmt2 = _db!.prepare('DELETE FROM feed_sources WHERE id = ?');
    stmt2.execute([id]);
    stmt2.close();
  }

  static void deleteFeedSources(List<int> ids) {
    if (ids.isEmpty) return;
    final placeholders = ids.map((_) => '?').join(',');
    _db!.execute('DELETE FROM articles WHERE feed_source_id IN ($placeholders)', ids);
    _db!.execute('DELETE FROM feed_sources WHERE id IN ($placeholders)', ids);
  }

  // ==================== Articles ====================

  /// Lightweight query for list views — skips summary & content columns.
  static List<RssArticle> getArticles(int feedSourceId, {int page = 1, int size = 20}) {
    final offset = (page - 1) * size;
    final results = _db!.select(
      'SELECT id, feed_source_id, guid, title, link, author, published_at, is_read, is_starred, created_at FROM articles WHERE feed_source_id = ? ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?',
      [feedSourceId, size, offset],
    );
    return results.map((row) => RssArticle.fromMap(row)).toList();
  }

  static List<RssArticle> getAllArticles({int page = 1, int size = 20}) {
    final offset = (page - 1) * size;
    final results = _db!.select(
      'SELECT id, feed_source_id, guid, title, link, author, published_at, is_read, is_starred, created_at FROM articles ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?',
      [size, offset],
    );
    return results.map((row) => RssArticle.fromMap(row)).toList();
  }

  /// Get articles from multiple feed sources (for folder view).
  static List<RssArticle> getArticlesByFeedIds(List<int> feedIds, {int page = 1, int size = 20}) {
    if (feedIds.isEmpty) return [];
    final offset = (page - 1) * size;
    final placeholders = feedIds.map((_) => '?').join(',');
    final results = _db!.select(
      'SELECT id, feed_source_id, guid, title, link, author, published_at, is_read, is_starred, created_at FROM articles WHERE feed_source_id IN ($placeholders) ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?',
      [...feedIds, size, offset],
    );
    return results.map((row) => RssArticle.fromMap(row)).toList();
  }

  /// Fetch full article (with summary & content) by id — used by detail screen.
  static RssArticle? getArticle(int id) {
    final results = _db!.select('SELECT * FROM articles WHERE id = ?', [id]);
    if (results.isEmpty) return null;
    return RssArticle.fromMap(results.first);
  }

  static int getArticleCount(int feedSourceId) {
    final result = _db!.select('SELECT COUNT(*) as cnt FROM articles WHERE feed_source_id = ?', [feedSourceId]);
    return result.first['cnt'] as int;
  }

  static int getUnreadCount(int feedSourceId) {
    final result = _db!.select(
      'SELECT COUNT(*) as cnt FROM articles WHERE feed_source_id = ? AND is_read = 0',
      [feedSourceId],
    );
    return result.first['cnt'] as int;
  }

  static int getTotalUnreadCount() {
    final result = _db!.select('SELECT COUNT(*) as cnt FROM articles WHERE is_read = 0');
    return result.first['cnt'] as int;
  }

  static RssArticle? getArticleByGuid(int feedSourceId, String guid) {
    final results = _db!.select(
      'SELECT * FROM articles WHERE feed_source_id = ? AND guid = ?',
      [feedSourceId, guid],
    );
    if (results.isEmpty) return null;
    return RssArticle.fromMap(results.first);
  }

  static int insertArticle(RssArticle article) {
    final stmt = _db!.prepare('''
      INSERT OR IGNORE INTO articles (feed_source_id, guid, title, link, author, summary, content, published_at, is_read, is_starred, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ''');
    stmt.execute([
      article.feedSourceId,
      article.guid,
      article.title,
      article.link,
      article.author,
      article.summary,
      article.content,
      article.publishedAt,
      article.isRead ? 1 : 0,
      article.isStarred ? 1 : 0,
    ]);
    final lastId = _db!.lastInsertRowId;
    stmt.close();
    return lastId;
  }

  static List<RssArticle> getStarredArticles({int page = 1, int size = 20}) {
    final offset = (page - 1) * size;
    final results = _db!.select(
      'SELECT id, feed_source_id, guid, title, link, author, published_at, is_read, is_starred, created_at FROM articles WHERE is_starred = 1 ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?',
      [size, offset],
    );
    return results.map((row) => RssArticle.fromMap(row)).toList();
  }

  static void markAsRead(int articleId) {
    final stmt = _db!.prepare('UPDATE articles SET is_read = 1 WHERE id = ?');
    stmt.execute([articleId]);
    stmt.close();
  }

  static void markAllAsRead(int feedSourceId) {
    final stmt = _db!.prepare('UPDATE articles SET is_read = 1 WHERE feed_source_id = ? AND is_read = 0');
    stmt.execute([feedSourceId]);
    stmt.close();
  }

  static void toggleStar(int articleId) {
    final stmt = _db!.prepare('UPDATE articles SET is_starred = CASE WHEN is_starred = 1 THEN 0 ELSE 1 END WHERE id = ?');
    stmt.execute([articleId]);
    stmt.close();
  }

  static void deleteArticlesBefore(DateTime date) {
    final stmt = _db!.prepare('DELETE FROM articles WHERE published_at < ?');
    stmt.execute([date.toUtc().toIso8601String()]);
    stmt.close();
  }

  static void deleteAllArticles() {
    _db!.execute('DELETE FROM articles');
  }

  static void deleteArticle(int id) {
    final stmt = _db!.prepare('DELETE FROM articles WHERE id = ?');
    stmt.execute([id]);
    stmt.close();
  }

  static void clearFeedArticles(int feedSourceId) {
    _db!.execute('DELETE FROM articles WHERE feed_source_id = ?', [feedSourceId]);
  }

  static void clearHistory({int? feedSourceId, DateTime? before}) {
    if (feedSourceId != null && before != null) {
      _db!.execute(
        'DELETE FROM articles WHERE feed_source_id = ? AND published_at < ?',
        [feedSourceId, before.toUtc().toIso8601String()],
      );
    } else if (feedSourceId != null) {
      _db!.execute('DELETE FROM articles WHERE feed_source_id = ?', [feedSourceId]);
    } else if (before != null) {
      _db!.execute('DELETE FROM articles WHERE published_at < ?', [before.toUtc().toIso8601String()]);
    } else {
      _db!.execute('DELETE FROM articles');
    }
  }

  // ==================== Folders ====================

  static List<Map<String, dynamic>> getAllFolders() {
    final results = _db!.select('SELECT * FROM rss_folders ORDER BY created_at DESC');
    return results.map((row) {
      final countResult = _db!.select(
        'SELECT COUNT(*) as cnt FROM rss_folder_items WHERE folder_id = ?',
        [row['id']],
      );
      return {
        ...row,
        'source_count': countResult.first['cnt'] as int,
      };
    }).toList();
  }

  static Map<String, dynamic>? getFolder(int id) {
    final results = _db!.select('SELECT * FROM rss_folders WHERE id = ?', [id]);
    if (results.isEmpty) return null;
    final row = results.first;
    final countResult = _db!.select(
      'SELECT COUNT(*) as cnt FROM rss_folder_items WHERE folder_id = ?',
      [id],
    );
    return {
      ...row,
      'source_count': countResult.first['cnt'] as int,
    };
  }

  static int createFolder(String name, String description) {
    final stmt = _db!.prepare(
      "INSERT INTO rss_folders (name, description, created_at, updated_at) VALUES (?, ?, datetime('now'), datetime('now'))"
    );
    stmt.execute([name, description]);
    final lastId = _db!.lastInsertRowId;
    stmt.close();
    return lastId;
  }

  static void updateFolder(int id, String name, String description) {
    final stmt = _db!.prepare(
      "UPDATE rss_folders SET name = ?, description = ?, updated_at = datetime('now') WHERE id = ?"
    );
    stmt.execute([name, description, id]);
    stmt.close();
  }

  static void deleteFolder(int id) {
    _db!.execute('DELETE FROM rss_folder_items WHERE folder_id = ?', [id]);
    _db!.execute('DELETE FROM rss_folders WHERE id = ?', [id]);
  }

  static List<FeedSource> getFolderSources(int folderId) {
    final results = _db!.select(
      '''SELECT fs.* FROM feed_sources fs
         INNER JOIN rss_folder_items fi ON fs.id = fi.source_id
         WHERE fi.folder_id = ?
         ORDER BY fi.created_at DESC''',
      [folderId],
    );
    return results.map((row) => FeedSource.fromMap(row)).toList();
  }

  static void addSourceToFolder(int folderId, int sourceId) {
    final stmt = _db!.prepare(
      "INSERT OR IGNORE INTO rss_folder_items (folder_id, source_id, created_at) VALUES (?, ?, datetime('now'))"
    );
    stmt.execute([folderId, sourceId]);
    stmt.close();
  }

  static void removeSourceFromFolder(int folderId, int sourceId) {
    _db!.execute(
      'DELETE FROM rss_folder_items WHERE folder_id = ? AND source_id = ?',
      [folderId, sourceId],
    );
  }

  static bool isSourceInFolder(int folderId, int sourceId) {
    final results = _db!.select(
      'SELECT 1 FROM rss_folder_items WHERE folder_id = ? AND source_id = ?',
      [folderId, sourceId],
    );
    return results.isNotEmpty;
  }

  /// 获取源被哪些收藏夹引用，返回 [{id, name}]
  static List<Map<String, dynamic>> getSourceFolderReferences(int sourceId) {
    final results = _db!.select(
      '''SELECT f.id, f.name FROM rss_folders f
         INNER JOIN rss_folder_items fi ON f.id = fi.folder_id
         WHERE fi.source_id = ?
         ORDER BY f.name''',
      [sourceId],
    );
    return results.map((row) => {'id': row['id'] as int, 'name': row['name'] as String}).toList();
  }

  static void close() {
    _db?.close();
    _db = null;
  }
}
