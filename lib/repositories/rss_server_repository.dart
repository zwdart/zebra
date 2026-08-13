import '../models/feed_source.dart';
import '../services/rss_api_service.dart';

/// 服务端(RSS 服务器模式)数据访问层。
/// 与 RssRepository 委托 RssDatabaseService 的模式一致,本类委托 RssApiService,
/// Provider 持有本类实例调用,避免业务层直接依赖静态 API 类。
class RssServerRepository {
  /// 获取服务器上的 RSS 源列表(分页)
  Future<RssPageResult?> getSources({int page = 1, int size = 20}) {
    return RssApiService.getSources(page: page, size: size);
  }

  /// 获取服务器上的收藏夹列表
  Future<List<Map<String, dynamic>>?> getFolders({int page = 1, int size = 50}) {
    return RssApiService.getFolders(page: page, size: size);
  }

  /// 获取收藏夹内的 RSS 源列表
  Future<RssPageResult?> getFolderSources(int folderId, {int page = 1, int size = 50}) {
    return RssApiService.getFolderSources(folderId, page: page, size: size);
  }

  /// 从服务器拉取文章分页(?source_id=&page=&size=&search=&read=&starred=&days=)
  Future<List<dynamic>?> getServerArticles({
    int? sourceId,
    int page = 1,
    int size = 20,
    String? search,
    String? read,
    bool? starred,
    int? days,
  }) {
    return RssApiService.getServerArticles(
      sourceId: sourceId,
      page: page,
      size: size,
      search: search,
      read: read,
      starred: starred,
      days: days,
    );
  }

  /// 获取文章详情(含 content 全文)
  Future<Map<String, dynamic>?> getServerArticle(int id) {
    return RssApiService.getServerArticle(id);
  }

  /// 各源未读数汇总
  Future<Map<String, dynamic>?> getServerUnreadSummary() {
    return RssApiService.getServerUnreadSummary();
  }

  /// 服务器抓取状态(total/pending/failed/last_fetch_at/sources)
  Future<Map<String, dynamic>?> getServerSyncStatus() {
    return RssApiService.getServerSyncStatus();
  }

  /// 触发服务器立即抓取
  Future<bool> triggerServerSync() {
    return RssApiService.triggerServerSync();
  }

  /// 同步单篇文章状态(已读/星标)
  Future<bool> updateServerArticleState(int id, {bool? read, bool? starred}) {
    return RssApiService.updateServerArticleState(id, read: read, starred: starred);
  }

  /// 创建 RSS 源
  Future<FeedSource?> createSource(FeedSource source) {
    return RssApiService.createSource(source);
  }

  /// 更新 RSS 源
  Future<bool> updateSource(FeedSource source) {
    return RssApiService.updateSource(source);
  }

  /// 删除 RSS 源
  Future<bool> deleteSource(int id) {
    return RssApiService.deleteSource(id);
  }

  /// 批量删除 RSS 源
  Future<bool> batchDelete(List<int> ids) {
    return RssApiService.batchDelete(ids);
  }
}
