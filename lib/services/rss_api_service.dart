import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  static String get _baseUrl => UpdateService.apiBaseUrl;

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

  /// 从 URL 抓取并解析 RSS/Atom feed
  static Future<Map<String, dynamic>> fetchFeed(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
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
