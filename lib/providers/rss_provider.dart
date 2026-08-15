import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/feed_source.dart';
import '../models/rss_article.dart';
import '../repositories/rss_repository.dart';
import '../repositories/rss_server_repository.dart';
import '../services/rss_api_service.dart';
import '../utils/rss_url.dart';

/// 视图模式：全部 / 星标 / 文件夹
enum ViewMode { all, starred, folder }

class RssProvider extends ChangeNotifier {
  final RssRepository _repository = RssRepository();
  final RssServerRepository _serverRepository = RssServerRepository();
  static const _prefKeySyncInterval = 'rss_sync_interval_minutes';
  static const _prefKeyServerMode = 'rss_server_mode';
  static const _prefKeyServerUrl = 'rss_server_url';
  static const _prefKeyServerSyncDays = 'rss_server_sync_days';

  List<FeedSource> _feeds = [];
  List<RssArticle> _articles = [];
  FeedSource? _currentFeed;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  int _articlePage = 1;
  bool _hasMoreArticles = true;
  Timer? _syncTimer;
  int _syncIntervalMinutes = 30;

  // server 模式状态
  bool _serverMode = false;
  String _serverUrl = '';
  int _serverSyncDays = 30;
  final Map<int, int> _serverUnreadBySource = {};
  int _serverTotalUnread = 0;
  FeedSource? _serverSelectedSource;
  bool _serverStarredOnly = false;

  // keyset 分页游标
  String? _lastCursorCreatedAt;
  int? _lastCursorId;

  // 搜索模式状态
  bool _isSearchMode = false;
  String _searchKeyword = '';

  // 视图模式状态
  ViewMode _viewMode = ViewMode.all;
  int? _selectedFolderId;
  String _selectedFolderName = '';

  List<FeedSource> get feeds => _feeds;
  List<RssArticle> get articles => _articles;
  FeedSource? get currentFeed => _currentFeed;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  bool get hasMoreArticles => _hasMoreArticles;
  int get totalUnreadCount => _repository.getTotalUnreadCount();
  int get syncIntervalMinutes => _syncIntervalMinutes;

  // server 模式
  bool get serverMode => _serverMode;
  String get serverUrl => _serverUrl;
  int get serverSyncDays => _serverSyncDays;
  int get serverTotalUnread => _serverTotalUnread;
  FeedSource? get serverSelectedSource => _serverSelectedSource;
  bool get serverStarredOnly => _serverStarredOnly;

  /// server 模式：某源未读数（来自服务器汇总）
  int getServerUnreadForSource(int sourceId) => _serverUnreadBySource[sourceId] ?? 0;

  // 搜索模式
  bool get isSearchMode => _isSearchMode;
  String get searchKeyword => _searchKeyword;

  // 视图模式
  ViewMode get viewMode => _viewMode;
  int? get selectedFolderId => _selectedFolderId;
  String get selectedFolderName => _selectedFolderName;

  void switchToAll() {
    _viewMode = ViewMode.all;
    _selectedFolderId = null;
    _selectedFolderName = '';
    loadAllArticles(refresh: true);
  }

  void switchToStarred() {
    _viewMode = ViewMode.starred;
    _selectedFolderId = null;
    _selectedFolderName = '';
    loadStarredArticles(refresh: true);
  }

  void switchToFolder(int folderId, String folderName) {
    _viewMode = ViewMode.folder;
    _selectedFolderId = folderId;
    _selectedFolderName = folderName;
    loadFolderArticles(folderId, refresh: true);
  }

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

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _syncIntervalMinutes = prefs.getInt(_prefKeySyncInterval) ?? 30;
    _serverMode = prefs.getBool(_prefKeyServerMode) ?? false;
    _serverUrl = prefs.getString(_prefKeyServerUrl) ?? '';
    _serverSyncDays = prefs.getInt(_prefKeyServerSyncDays) ?? 30;
    // server 模式基址同步到 RssApiService（供测试连接与加载使用）
    RssApiService.rssServerBaseUrl = _serverMode ? _serverUrl : null;
    loadFeedSources();
    _startAutoSync();
    // server 模式启动时自动加载服务器数据
    if (_serverMode) {
      loadServerAll();
    }
    // 启动时检查自动备份（每 7 天一次）
    _repository.maybeAutoBackup();
  }

  // ==================== Server 模式 ====================

  /// 设置 server 模式（开关 + 服务器地址），持久化并切换数据源
  Future<void> setServerMode(bool enabled, {String url = ''}) async {
    _serverMode = enabled;
    if (enabled && url.isNotEmpty) {
      _serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    }
    // 同步 RSS API 基址：开启用独立地址，关闭回退主 API 地址
    RssApiService.rssServerBaseUrl = _serverMode ? _serverUrl : null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyServerMode, _serverMode);
    if (enabled) await prefs.setString(_prefKeyServerUrl, _serverUrl);
    notifyListeners();
    // 切换数据源：开启时加载服务器数据，关闭时恢复本地数据。
    // 否则 _feeds/_articles 共享槽位会残留另一套数据（在线/离线混在一起）。
    if (enabled) {
      await loadServerAll();
    } else {
      loadFeedSources();
      loadAllArticles(refresh: true);
    }
  }

  /// 服务器源列表（server 模式下拉取）
  Future<List<Map<String, dynamic>>?> fetchServerSources() async {
    final result = await _serverRepository.getSources(size: 100);
    if (result == null) return null;
    return result.sources
        .map((s) => s.toJson())
        .toList();
  }

  /// server 模式：选择数据源（null=全部），与星标筛选互斥
  void selectServerSource(FeedSource? source) {
    _serverSelectedSource = source;
    _serverStarredOnly = false;
    notifyListeners();
    loadServerArticles(sourceId: source?.id, refresh: true);
  }

  /// server 模式：设置本地同步时间窗口(天),持久化
  Future<void> setServerSyncDays(int days) async {
    if (days <= 0) return;
    _serverSyncDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyServerSyncDays, days);
    notifyListeners();
  }

  /// server 模式：切换星标筛选，与数据源筛选互斥
  void toggleServerStarredOnly() {
    _serverStarredOnly = !_serverStarredOnly;
    if (_serverStarredOnly) _serverSelectedSource = null;
    notifyListeners();
    loadServerArticles(starredOnly: _serverStarredOnly, refresh: true);
  }

  /// server 模式：从服务器拉取文章流（全部/星标/搜索）
  /// [refresh]=true 重置分页并替换列表；false 追加下一页（加载更多）
  Future<void> loadServerArticles({
    int? sourceId,
    bool starredOnly = false,
    String? search,
    bool refresh = true,
  }) async {
    if (refresh) {
      _resetPager();
      _articles = [];
    }
    _isLoading = true;
    _error = null;
    notifyListeners();

    final data = await _serverRepository.getServerArticles(
      sourceId: sourceId,
      page: _articlePage,
      size: 20,
      search: search,
      read: null,
      starred: starredOnly ? true : null,
    );

    _isLoading = false;
    if (data == null) {
      _error = 'rssSyncFailed';
      notifyListeners();
      return;
    }

    final loaded = data.map((e) {
      final m = e as Map<String, dynamic>;
      return RssArticle(
        id: m['id'] as int?,
        feedSourceId: (m['source_id'] as int?) ?? 0,
        guid: m['guid'] as String? ?? '',
        title: m['title'] as String? ?? '',
        link: m['link'] as String? ?? '',
        author: m['author'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        content: m['content'] as String? ?? '',
        publishedAt: m['published_at'] as String?,
        isRead: m['is_read'] as bool? ?? false,
        isStarred: m['is_starred'] as bool? ?? false,
        createdAt: m['created_at'] as String?,
      );
    }).toList();
    _articles = refresh ? loaded : [..._articles, ...loaded];
    _hasMoreArticles = loaded.length >= 20;
    notifyListeners();
  }

  /// server 模式：一次性加载全部数据（服务器源列表 + 未读汇总 + 全部文章流）
  Future<void> loadServerAll() async {
    _viewMode = ViewMode.all;
    _currentFeed = null;
    _selectedFolderId = null;
    _selectedFolderName = '';
    _isSearchMode = false;
    _searchKeyword = '';
    // 刷新/重置后自动回到「全部」选中,清除数据源/星标筛选
    _serverSelectedSource = null;
    _serverStarredOnly = false;

    final sources = await _serverRepository.getSources(size: 100);
    if (sources != null) {
      _feeds = sources.sources;
    }
    await refreshServerUnread();
    await loadServerArticles(refresh: true);
  }

  /// server 模式：触发服务器抓取并重新加载全部数据（下拉刷新用）
  Future<void> syncServerNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _error = null;
    notifyListeners();
    await _serverRepository.triggerServerSync();
    await loadServerAll();
    _isSyncing = false;
    notifyListeners();
  }

  /// 把服务器上已订阅源的文章同步到本地数据库(离线可读)。
  /// 以【本地已订阅源】为准遍历:对每个本地源按 url 匹配服务器源,
  /// 匹配上才拉取该源最近 N 天文章写入本地;服务器有而本地未订阅的源不处理。
  /// [days]>0 时仅同步最近 N 天入库的文章(服务端按 UTC 计算,避免时区偏差)。
  /// 复用 (feed_source_id, guid) 唯一索引去重,返回本次真正新增的文章数。
  Future<int> syncServerSourcesToLocal({int days = 30}) async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    _error = null;
    notifyListeners();

    var newCount = 0;
    try {
      // 服务器源列表 → 归一化 url 映射(用于匹配本地已订阅源)
      final result = await _serverRepository.getSources(size: 100);
      final serverByNormUrl = <String, FeedSource>{
        for (final s in (result?.sources ?? [])) normalizeRssUrl(s.url): s,
      };

      // 遍历本地已订阅源:url 匹配上服务器源才拉取文章
      for (final local in _repository.getAllFeedSources()) {
        final server = serverByNormUrl[normalizeRssUrl(local.url)];
        final localId = local.id;
        if (server == null || localId == null) continue;

        // 分页拉取该源最近 N 天文章,写入本地库
        var page = 1;
        while (true) {
          final list = await _serverRepository.getServerArticles(
            sourceId: server.id,
            page: page,
            size: 100,
            days: days,
          );
          if (list == null || list.isEmpty) break;
          for (final e in list) {
            final m = e as Map<String, dynamic>;
            final article = RssArticle(
              id: null,
              feedSourceId: localId,
              guid: m['guid'] as String? ?? '',
              title: m['title'] as String? ?? '',
              link: m['link'] as String? ?? '',
              author: m['author'] as String? ?? '',
              summary: m['summary'] as String? ?? '',
              content: m['content'] as String? ?? '',
              publishedAt: m['published_at'] as String?,
              isRead: m['is_read'] as bool? ?? false,
              isStarred: m['is_starred'] as bool? ?? false,
              createdAt: m['created_at'] as String?,
            );
            if (_repository.insertArticle(article)) newCount++;
          }
          if (list.length < 100) break;
          page++;
        }
      }
      loadFeedSources();
    } catch (e) {
      _error = 'rssSyncFailed';
    }

    _isSyncing = false;
    notifyListeners();
    return newCount;
  }

  /// server 模式：已读/星标状态同步到服务器（乐观更新本地）
  void syncServerState(int articleId, {bool? read, bool? starred}) {
    if (read != null) {
      read ? markAsRead(articleId) : markAsUnread(articleId);
    }
    if (starred != null) {
      final a = _articles.where((x) => x.id == articleId).toList();
      if (a.isNotEmpty && a.first.isStarred != starred) toggleStar(articleId);
    }
    _serverRepository.updateServerArticleState(articleId, read: read, starred: starred);
  }

  /// server 模式：拉取各源未读数汇总并缓存
  Future<void> refreshServerUnread() async {
    final summary = await _serverRepository.getServerUnreadSummary();
    if (summary == null) return;
    final data = summary['data'] as List<dynamic>? ?? [];
    _serverUnreadBySource.clear();
    _serverTotalUnread = 0;
    for (final item in data) {
      final m = item as Map<String, dynamic>;
      final sid = (m['source_id'] as int?) ?? 0;
      final unread = (m['unread'] as int?) ?? 0;
      _serverUnreadBySource[sid] = unread;
      _serverTotalUnread += unread;
    }
    notifyListeners();
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
        _error = 'rssFeedExists';
        notifyListeners();
        return false;
      }
      _repository.addFeedSource(source);
      loadFeedSources();
      return true;
    } catch (e) {
      _error = 'rssAddFailed';
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
        _error = 'rssFeedExists';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // First save the source to get an ID
      final source = FeedSource(title: title ?? url, url: url);
      final id = _repository.addFeedSource(source);
      final savedSource = _repository.getFeedSource(id);
      if (savedSource == null) {
        _error = 'rssAddFailed';
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
      _error = 'rssAddFailedCheckUrl';
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

  void _resetPager() {
    _articlePage = 1;
    _hasMoreArticles = true;
    _lastCursorCreatedAt = null;
    _lastCursorId = null;
  }

  void _updateCursor(List<RssArticle> newArticles) {
    if (newArticles.isNotEmpty) {
      _lastCursorCreatedAt = newArticles.last.createdAt;
      _lastCursorId = newArticles.last.id;
    }
  }

  void loadArticles(int feedSourceId, {bool refresh = false}) {
    if (refresh) {
      _resetPager();
      _articles = [];
    }
    _currentFeed = _repository.getFeedSource(feedSourceId);
    final newArticles = _repository.getArticles(feedSourceId,
        page: _articlePage,
        beforeCreatedAt: _lastCursorCreatedAt,
        beforeId: _lastCursorId);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _updateCursor(newArticles);
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  void loadMoreArticles() {
    if (!_hasMoreArticles) return;
    _articlePage++;
    if (_isSearchMode) {
      searchArticles(_searchKeyword);
      return;
    }
    if (_serverMode) {
      loadServerArticles(
        sourceId: _currentFeed?.id,
        starredOnly: _viewMode == ViewMode.starred,
        refresh: false,
      );
      return;
    }
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
      _resetPager();
      _articles = [];
    }
    _currentFeed = null;
    final newArticles = _repository.getAllArticles(
        page: _articlePage,
        beforeCreatedAt: _lastCursorCreatedAt,
        beforeId: _lastCursorId);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _updateCursor(newArticles);
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  void loadStarredArticles({bool refresh = false}) {
    if (refresh) {
      _resetPager();
      _articles = [];
    }
    _currentFeed = null;
    final newArticles = _repository.getStarredArticles(
        page: _articlePage,
        beforeCreatedAt: _lastCursorCreatedAt,
        beforeId: _lastCursorId);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _updateCursor(newArticles);
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  /// Load articles from a specific folder (articles from all sources in that folder).
  int? _currentFolderId;

  int? get currentFolderId => _currentFolderId;

  void loadFolderArticles(int folderId, {bool refresh = false}) {
    if (refresh) {
      _resetPager();
      _articles = [];
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
    final newArticles = _repository.getArticlesByFeedIds(feedIds,
        page: _articlePage,
        beforeCreatedAt: _lastCursorCreatedAt,
        beforeId: _lastCursorId);
    if (refresh) {
      _articles = newArticles;
    } else {
      _articles = [..._articles, ...newArticles];
    }
    _updateCursor(newArticles);
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  /// 全文搜索：进入搜索模式并加载结果
  void searchArticles(String keyword) {
    final k = keyword.trim();
    _isSearchMode = true;
    _searchKeyword = k;
    _resetPager();
    _articles = [];
    if (k.isEmpty) {
      _hasMoreArticles = false;
      notifyListeners();
      return;
    }
    final newArticles = _repository.searchArticles(k,
        page: _articlePage,
        beforeCreatedAt: _lastCursorCreatedAt,
        beforeId: _lastCursorId);
    _articles = newArticles;
    _updateCursor(newArticles);
    _hasMoreArticles = newArticles.length >= 20;
    notifyListeners();
  }

  /// 退出搜索模式，回到全部文章视图
  void exitSearch() {
    if (!_isSearchMode) return;
    _isSearchMode = false;
    _searchKeyword = '';
    loadAllArticles(refresh: true);
  }

  /// Fetch full article (with summary & content) by id.
  RssArticle? getArticle(int id) {
    return _repository.getArticle(id);
  }

  void markAsRead(int articleId) {
    try {
      _repository.markAsRead(articleId);
    } catch (e) {
      debugPrint('markAsRead failed: $e');
      return;
    }
    final index = _articles.indexWhere((a) => a.id == articleId);
    if (index >= 0) {
      _articles[index] = _articles[index].copyWith(isRead: true);
    }
    notifyListeners();
  }

  void markAsUnread(int articleId) {
    try {
      _repository.markAsUnread(articleId);
    } catch (e) {
      debugPrint('markAsUnread failed: $e');
      return;
    }
    final index = _articles.indexWhere((a) => a.id == articleId);
    if (index >= 0) {
      _articles[index] = _articles[index].copyWith(isRead: false);
    }
    notifyListeners();
  }

  void markAllAsRead(int feedSourceId) {
    try {
      _repository.markAllAsRead(feedSourceId);
    } catch (e) {
      debugPrint('markAllAsRead failed: $e');
      return;
    }
    _articles = _articles.map((a) {
      if (a.feedSourceId == feedSourceId) return a.copyWith(isRead: true);
      return a;
    }).toList();
    notifyListeners();
  }

  void toggleStar(int articleId) {
    try {
      _repository.toggleStar(articleId);
    } catch (e) {
      debugPrint('toggleStar failed: $e');
      return;
    }
    final index = _articles.indexWhere((a) => a.id == articleId);
    if (index >= 0) {
      final article = _articles[index];
      _articles[index] = article.copyWith(isStarred: !article.isStarred);
    }
    notifyListeners();
  }

  void deleteArticle(int articleId) {
    try {
      _repository.deleteArticle(articleId);
    } catch (e) {
      debugPrint('deleteArticle failed: $e');
      return;
    }
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

  // 同步进度状态
  String? _syncingFeedTitle;
  int _syncedCount = 0;
  int _totalSyncCount = 0;

  String? get syncingFeedTitle => _syncingFeedTitle;
  int get syncedCount => _syncedCount;
  int get totalSyncCount => _totalSyncCount;
  double get syncProgress =>
      _totalSyncCount == 0 ? 0 : _syncedCount / _totalSyncCount;

  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _error = null;
    _syncingFeedTitle = null;
    _syncedCount = 0;
    _totalSyncCount = 0;
    notifyListeners();

    try {
      await _repository.syncAllFeedSources(onProgress: (done, total, title) {
        _syncedCount = done;
        _totalSyncCount = total;
        _syncingFeedTitle = title;
        notifyListeners();
      });
      loadFeedSources();
      if (_currentFeed != null) {
        loadArticles(_currentFeed!.id!, refresh: true);
      } else {
        loadAllArticles(refresh: true);
      }
    } catch (e) {
      _error = 'rssSyncFailed';
    }

    _isSyncing = false;
    _syncingFeedTitle = null;
    notifyListeners();
  }

  Future<void> syncFeedSourceById(int feedSourceId) async {
    final source = _repository.getFeedSource(feedSourceId);
    if (source == null) return;

    _isSyncing = true;
    _syncingFeedTitle = source.title;
    _syncedCount = 0;
    _totalSyncCount = 1;
    notifyListeners();

    try {
      await _repository.syncFeedSource(source);
      loadFeedSources();
      if (_currentFeed?.id == feedSourceId) {
        loadArticles(feedSourceId, refresh: true);
      }
    } catch (e) {
      _error = 'rssSyncFailed';
    }

    _isSyncing = false;
    _syncingFeedTitle = null;
    notifyListeners();
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(minutes: _syncIntervalMinutes), (_) {
      syncAll();
    });
  }

  /// 设置同步间隔（分钟），持久化并重启定时器
  Future<void> setSyncIntervalMinutes(int minutes) async {
    if (minutes < 1) return;
    _syncIntervalMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeySyncInterval, minutes);
    _startAutoSync();
    notifyListeners();
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

  String exportToCsvForSources(List<FeedSource> sources) => _repository.exportToCsv(sources);

  List<FeedSource> importFromCsv(String csv) => _repository.importFromCsv(csv);

  String exportToOpml() => _repository.exportToOpml(_feeds);

  String exportToOpmlForSources(List<FeedSource> sources) => _repository.exportToOpml(sources);

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

  // ==================== Auto Backup ====================

  Future<bool> isAutoBackupEnabled() => _repository.isAutoBackupEnabled();

  Future<void> setAutoBackupEnabled(bool enabled) async {
    await _repository.setAutoBackupEnabled(enabled);
    notifyListeners();
  }

  Future<bool> backupNow() => _repository.writeBackupNow();

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
    final result = await _serverRepository.getFolderSources(folderId, size: 100);
    if (result == null) return 0;
    var added = 0;
    for (final source in result.sources) {
      final success = await addFeedSource(source);
      if (success) added++;
    }
    return added;
  }
}
