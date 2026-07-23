import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/feed_source.dart';
import '../models/rss_article.dart';
import '../repositories/rss_repository.dart';
import '../services/rss_api_service.dart';

class RssProvider extends ChangeNotifier {
  final RssRepository _repository = RssRepository();

  List<FeedSource> _feeds = [];
  List<RssArticle> _articles = [];
  FeedSource? _currentFeed;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  int _articlePage = 1;
  bool _hasMoreArticles = true;
  Timer? _syncTimer;

  List<FeedSource> get feeds => _feeds;
  List<RssArticle> get articles => _articles;
  FeedSource? get currentFeed => _currentFeed;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  bool get hasMoreArticles => _hasMoreArticles;
  int get totalUnreadCount => _repository.getTotalUnreadCount();

  String getFeedTitle(int feedSourceId) {
    final feed = _feeds.where((f) => f.id == feedSourceId).toList();
    return feed.isNotEmpty ? feed.first.title : '';
  }

  int getUnreadCountForFeed(int feedSourceId) {
    return _repository.getUnreadCount(feedSourceId);
  }

  FeedSource? getFeedSourceByUrl(String url) {
    return _repository.getFeedSourceByUrl(url);
  }

  void init() {
    loadFeedSources();
    _startAutoSync();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  // ==================== Feed Sources ====================

  void loadFeedSources() {
    _feeds = _repository.getAllFeedSources();
    notifyListeners();
  }

  Future<bool> addFeedSource(FeedSource source) async {
    _error = null;
    try {
      final existing = _repository.getFeedSourceByUrl(source.url);
      if (existing != null) {
        _error = '该订阅源已存在';
        notifyListeners();
        return false;
      }
      _repository.addFeedSource(source);
      loadFeedSources();
      return true;
    } catch (e) {
      _error = '添加失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addFeedSourceFromUrl(String url, {String? title}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final existing = _repository.getFeedSourceByUrl(url);
      if (existing != null) {
        _error = '该订阅源已存在';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // First save the source to get an ID
      final source = FeedSource(title: title ?? url, url: url);
      final id = _repository.addFeedSource(source);
      final savedSource = _repository.getFeedSource(id);
      if (savedSource == null) {
        _error = '添加失败';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Then sync to fetch articles
      await _repository.syncFeedSource(savedSource);

      _isLoading = false;
      loadFeedSources();
      return true;
    } catch (e) {
      _error = '添加失败，请检查URL是否正确: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void updateFeedSource(FeedSource source) {
    _repository.updateFeedSource(source);
    loadFeedSources();
  }

  void deleteFeedSource(int id) {
    _repository.deleteFeedSource(id);
    if (_currentFeed?.id == id) {
      _currentFeed = null;
      _articles = [];
    }
    loadFeedSources();
    notifyListeners();
  }

  Future<bool> bookmarkFromServer(FeedSource serverSource) async {
    final success = await _repository.bookmarkFromServer(serverSource);
    if (success) loadFeedSources();
    return success;
  }

  // ==================== Articles ====================

  void loadArticles(int feedSourceId, {bool refresh = false}) {
    if (refresh) {
      _articlePage = 1;
      _articles = [];
      _hasMoreArticles = true;
    }
    _currentFeed = _repository.getFeedSource(feedSourceId);
    final newArticles = _repository.getArticles(feedSourceId, page: _articlePage);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  void loadMoreArticles() {
    if (!_hasMoreArticles) return;
    _articlePage++;
    if (_currentFeed != null) {
      loadArticles(_currentFeed!.id!);
    } else if (_currentFolderId != null) {
      loadFolderArticles(_currentFolderId!);
    } else {
      loadAllArticles();
    }
  }

  void loadAllArticles({bool refresh = false}) {
    if (refresh) {
      _articlePage = 1;
      _articles = [];
      _hasMoreArticles = true;
    }
    _currentFeed = null;
    final newArticles = _repository.getAllArticles(page: _articlePage);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  void loadStarredArticles({bool refresh = false}) {
    if (refresh) {
      _articlePage = 1;
      _articles = [];
      _hasMoreArticles = true;
    }
    _currentFeed = null;
    final newArticles = _repository.getStarredArticles(page: _articlePage);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  /// Load articles from a specific folder (articles from all sources in that folder).
  int? _currentFolderId;

  int? get currentFolderId => _currentFolderId;

  void loadFolderArticles(int folderId, {bool refresh = false}) {
    if (refresh) {
      _articlePage = 1;
      _articles = [];
      _hasMoreArticles = true;
    }
    _currentFeed = null;
    _currentFolderId = folderId;
    final sources = getFolderSources(folderId);
    final feedIds = sources.map((s) => s.id!).toList();
    if (feedIds.isEmpty) {
      _articles = [];
      _hasMoreArticles = false;
      notifyListeners();
      return;
    }
    final newArticles = _repository.getArticlesByFeedIds(feedIds, page: _articlePage);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  /// Fetch full article (with summary & content) by id.
  RssArticle? getArticle(int id) {
    return _repository.getArticle(id);
  }

  void markAsRead(int articleId) {
    _repository.markAsRead(articleId);
    final index = _articles.indexWhere((a) => a.id == articleId);
    if (index >= 0) {
      _articles[index] = _articles[index].copyWith(isRead: true);
    }
    notifyListeners();
  }

  void markAllAsRead(int feedSourceId) {
    _repository.markAllAsRead(feedSourceId);
    _articles = _articles.map((a) {
      if (a.feedSourceId == feedSourceId) return a.copyWith(isRead: true);
      return a;
    }).toList();
    notifyListeners();
  }

  void toggleStar(int articleId) {
    _repository.toggleStar(articleId);
    final index = _articles.indexWhere((a) => a.id == articleId);
    if (index >= 0) {
      final article = _articles[index];
      _articles[index] = article.copyWith(isStarred: !article.isStarred);
    }
    notifyListeners();
  }

  void deleteArticle(int articleId) {
    _repository.deleteArticle(articleId);
    _articles.removeWhere((a) => a.id == articleId);
    notifyListeners();
  }

  void clearFeedArticles(int feedSourceId) {
    _repository.clearFeedArticles(feedSourceId);
    _articles.removeWhere((a) => a.feedSourceId == feedSourceId);
    loadFeedSources();
    notifyListeners();
  }

  // ==================== Sync ====================

  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.syncAllFeedSources();
      loadFeedSources();
      if (_currentFeed != null) {
        loadArticles(_currentFeed!.id!, refresh: true);
      } else {
        loadAllArticles(refresh: true);
      }
    } catch (e) {
      _error = '同步失败: $e';
    }

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> syncFeedSourceById(int feedSourceId) async {
    final source = _repository.getFeedSource(feedSourceId);
    if (source == null) return;

    _isSyncing = true;
    notifyListeners();

    try {
      await _repository.syncFeedSource(source);
      loadFeedSources();
      if (_currentFeed?.id == feedSourceId) {
        loadArticles(feedSourceId, refresh: true);
      }
    } catch (e) {
      _error = '同步失败: $e';
    }

    _isSyncing = false;
    notifyListeners();
  }

  void _startAutoSync() {
    _syncTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      syncAll();
    });
  }

  // ==================== History ====================

  void clearHistory({int? feedSourceId, DateTime? before}) {
    _repository.clearHistory(feedSourceId: feedSourceId, before: before);
    if (_currentFeed != null) {
      loadArticles(_currentFeed!.id!, refresh: true);
    }
    loadFeedSources();
    notifyListeners();
  }

  // ==================== Import / Export ====================

  String exportToCsv() => _repository.exportToCsv(_feeds);

  List<FeedSource> importFromCsv(String csv) => _repository.importFromCsv(csv);

  String exportToOpml() => _repository.exportToOpml(_feeds);

  List<FeedSource> importFromOpml(String opml) => _repository.importFromOpml(opml);

  int importSources(List<FeedSource> sources) {
    var count = 0;
    for (final source in sources) {
      final existing = _repository.getFeedSourceByUrl(source.url);
      if (existing == null) {
        _repository.addFeedSource(source);
        count++;
      }
    }
    loadFeedSources();
    return count;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ==================== Folders ====================

  List<Map<String, dynamic>> getAllFolders() {
    return _repository.getAllFolders();
  }

  Map<String, dynamic>? getFolder(int id) {
    return _repository.getFolder(id);
  }

  int createFolder(String name, String description) {
    final id = _repository.createFolder(name, description);
    notifyListeners();
    return id;
  }

  void updateFolder(int id, String name, String description) {
    _repository.updateFolder(id, name, description);
    notifyListeners();
  }

  void deleteFolder(int id) {
    _repository.deleteFolder(id);
    notifyListeners();
  }

  List<FeedSource> getFolderSources(int folderId) {
    return _repository.getFolderSources(folderId);
  }

  void addSourceToFolder(int folderId, int sourceId) {
    _repository.addSourceToFolder(folderId, sourceId);
    notifyListeners();
  }

  void removeSourceFromFolder(int folderId, int sourceId) {
    _repository.removeSourceFromFolder(folderId, sourceId);
    notifyListeners();
  }

  bool isSourceInFolder(int folderId, int sourceId) {
    return _repository.isSourceInFolder(folderId, sourceId);
  }

  List<Map<String, dynamic>> getSourceFolderReferences(int sourceId) {
    return _repository.getSourceFolderReferences(sourceId);
  }

  Future<int> addFolderSourcesFromServer(int folderId) async {
    final result = await RssApiService.getFolderSources(folderId, size: 100);
    if (result == null) return 0;
    var added = 0;
    for (final source in result.sources) {
      final success = await addFeedSource(source);
      if (success) added++;
    }
    return added;
  }
}
