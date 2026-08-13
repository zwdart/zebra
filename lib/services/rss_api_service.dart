import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import '../models/feed_source.dart';
import 'update_service.dart';

class RssPageResult {
  final List<FeedSource> sources;
  final int total;
  final int page;
  final int size;

  const RssPageResult({
    required this.sources,
    required this.total,
    required this.page,
    required this.size,
  });

  bool get hasMore => page * size < total;
}

class RssApiService {
  /// 服务器模式专用基址（独立于主 API 地址，server 模式开启时由 Provider 设置）
  static String? rssServerBaseUrl;

  /// RSS API 基址：server 模式优先用独立地址，否则回退主 API 地址
  static String get _baseUrl {
    final rss = rssServerBaseUrl;
    return (rss != null && rss.isNotEmpty) ? rss : UpdateService.apiBaseUrl;
  }

  /// 获取服务器上的收藏夹列表
  static Future<List<Map<String, dynamic>>?> getFolders({int page = 1, int size = 50}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/rss/folders').replace(
        queryParameters: {'page': '$page', 'size': '$size'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>? ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (e) {
      debugPrint('Get RSS folders failed: $e');
      return null;
    }
  }

  // ==================== Server 模式文章流（S3 API） ====================

  /// 从服务器拉取文章分页（?source_id=&page=&size=&search=&read=&starred=&days=）
  /// [days]>0 时仅拉最近 N 天入库的文章（由服务端按 UTC 计算,避免时区偏差）
  static Future<List<dynamic>?> getServerArticles({
    int? sourceId,
    int page = 1,
    int size = 20,
    String? search,
    String? read,
    bool? starred,
    int? days,
  }) async {
    try {
      final params = <String, String>{'page': '$page', 'size': '$size'};
      if (sourceId != null) params['source_id'] = '$sourceId';
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (read != null) params['read'] = read;
      if (starred != null) params['starred'] = '$starred';
      if (days != null && days > 0) params['days'] = '$days';
      final uri = Uri.parse('$_baseUrl/api/rss/articles').replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['data'] as List<dynamic>? ?? [];
      }
      return null;
    } catch (e) {
      debugPrint('Get server articles failed: $e');
      return null;
    }
  }

  /// 获取文章详情（含 content 全文）
  static Future<Map<String, dynamic>?> getServerArticle(int id) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/rss/articles/$id'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('Get server article failed: $e');
      return null;
    }
  }

  /// 各源未读数汇总
  static Future<Map<String, dynamic>?> getServerUnreadSummary() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/rss/articles/unread'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Get server unread summary failed: $e');
      return null;
    }
  }

  /// 服务器抓取状态（total/pending/failed/last_fetch_at/sources）
  static Future<Map<String, dynamic>?> getServerSyncStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/rss/sync/status'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('Get server sync status failed: $e');
      return null;
    }
  }

  /// 触发服务器立即抓取
  static Future<bool> triggerServerSync() async {
    try {
      final response = await http
          .post(Uri.parse('$_baseUrl/api/rss/sync'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Trigger server sync failed: $e');
      return false;
    }
  }

  /// 同步单篇文章状态（已读/星标）
  static Future<bool> updateServerArticleState(int id, {bool? read, bool? starred}) async {
    try {
      final body = <String, dynamic>{};
      if (read != null) body['read'] = read;
      if (starred != null) body['starred'] = starred;
      if (body.isEmpty) return false;
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/api/rss/articles/$id/state'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Update server article state failed: $e');
      return false;
    }
  }

  /// 获取收藏夹内的 RSS 源列表
  static Future<RssPageResult?> getFolderSources(int folderId, {int page = 1, int size = 50}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/rss/folders/$folderId/sources').replace(
        queryParameters: {'page': '$page', 'size': '$size'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>? ?? [];
        final sources = data.map((e) => FeedSource.fromJson(e as Map<String, dynamic>)).toList();
        final total = json['total'] as int? ?? 0;
        return RssPageResult(sources: sources, total: total, page: page, size: size);
      }
      return null;
    } catch (e) {
      debugPrint('Get folder sources failed: $e');
      return null;
    }
  }

  /// 获取服务器上的 RSS 源列表（分页）
  static Future<RssPageResult?> getSources({int page = 1, int size = 20}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/rss/sources').replace(
        queryParameters: {'page': '$page', 'size': '$size'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>? ?? [];
        final sources = data.map((e) => FeedSource.fromJson(e as Map<String, dynamic>)).toList();
        final total = json['total'] as int? ?? 0;
        return RssPageResult(sources: sources, total: total, page: page, size: size);
      }
      return null;
    } catch (e) {
      debugPrint('Get RSS sources failed: $e');
      return null;
    }
  }

  /// 创建 RSS 源
  static Future<FeedSource?> createSource(FeedSource source) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/admin/rss/sources'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(source.toJson()),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          return FeedSource.fromJson(json['data'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Create RSS source failed: $e');
      return null;
    }
  }

  /// 更新 RSS 源
  static Future<bool> updateSource(FeedSource source) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/api/admin/rss/sources/${source.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(source.toJson()),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Update RSS source failed: $e');
      return false;
    }
  }

  /// 删除 RSS 源
  static Future<bool> deleteSource(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/admin/rss/sources/$id'),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete RSS source failed: $e');
      return false;
    }
  }

  /// 批量删除
  static Future<bool> batchDelete(List<int> ids) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/admin/rss/sources/batch-delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids}),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Batch delete RSS sources failed: $e');
      return false;
    }
  }

  /// 创建一个允许自签名证书的 HTTP 客户端（用于抓取 RSS 源）
  static http.Client _createClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(httpClient);
  }

  /// 从 URL 抓取并解析 RSS/Atom feed
  /// [ifModifiedSince] 传入上次同步时间（RFC 1123），源返回 304 时返回 {'notModified': true}
  static Future<Map<String, dynamic>> fetchFeed(String url, {String? ifModifiedSince}) async {
    final client = _createClient();
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (ifModifiedSince != null && ifModifiedSince.isNotEmpty) {
        request.headers['If-Modified-Since'] = ifModifiedSince;
      }
      final streamed = await client.send(request).timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 304) {
        return {'notModified': true};
      }
      if (response.statusCode == 200) {
        final body = _decodeBody(response.bodyBytes, response.headers['content-type']);
        return {'body': body, 'contentType': response.headers['content-type']};
      }
      // Non-200: return error info with truncated response body
      final body = _decodeBody(response.bodyBytes, response.headers['content-type']);
      final preview = body.length > 500 ? '${body.substring(0, 500)}...' : body;
      return {
        'error': 'HTTP ${response.statusCode}',
        'statusCode': response.statusCode,
        'body': preview,
      };
    } catch (e) {
      debugPrint('Fetch feed failed: $e');
      return {'error': e.toString()};
    } finally {
      client.close();
    }
  }

  /// 解码响应体，自动处理编码
  static String _decodeBody(Uint8List bytes, String? contentType) {
    // Try to detect encoding from Content-Type header
    Encoding? encoding;
    if (contentType != null) {
      final charsetMatch = RegExp(r'charset=([^\s;]+)', caseSensitive: false).firstMatch(contentType);
      if (charsetMatch != null) {
        final charset = charsetMatch.group(1)!.toLowerCase().trim();
        encoding = Encoding.getByName(charset);
      }
    }

    // If no encoding from header, try to detect from XML declaration
    if (encoding == null) {
      final preview = String.fromCharCodes(bytes.take(200));
      // Look for encoding="..." or encoding='...' in XML declaration
      final encIndex = preview.indexOf('encoding=');
      if (encIndex >= 0) {
        final afterEquals = preview.substring(encIndex + 9).trimLeft();
        if (afterEquals.isNotEmpty) {
          final quote = afterEquals[0];
          if (quote == '"' || quote == "'") {
            final endQuote = afterEquals.indexOf(quote, 1);
            if (endQuote > 1) {
              final encName = afterEquals.substring(1, endQuote).trim();
              encoding = Encoding.getByName(encName);
            }
          }
        }
      }
    }

    // Fallback to UTF-8, then Latin-1
    encoding ??= utf8;
    try {
      return encoding.decode(bytes);
    } catch (_) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return latin1.decode(bytes);
      }
    }
  }
}
