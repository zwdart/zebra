import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/blog_post.dart';
import 'update_service.dart';

class BlogService {
  static String get _baseUrl => UpdateService.apiBaseUrl;

  /// 获取已发布博客列表（分页）
  static Future<PaginatedBlogPosts?> getBlogPosts({
    int page = 1,
    int size = 10,
    String? search,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'size': '$size',
      };
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      final uri = Uri.parse('$_baseUrl/api/blog/posts').replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return PaginatedBlogPosts.fromJson(json);
      }
      return null;
    } catch (e) {
      debugPrint('Get blog posts failed: $e');
      return null;
    }
  }

  /// 获取单篇博客
  static Future<BlogPost?> getBlogPost(int id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/blog/posts/$id');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true && json['data'] != null) {
          return BlogPost.fromJson(json['data'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Get blog post failed: $e');
      return null;
    }
  }
}
