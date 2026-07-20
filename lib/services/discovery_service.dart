import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/discovery_item.dart';
import 'update_service.dart';

class DiscoveryService {
  static String get _baseUrl => UpdateService.apiBaseUrl;

  /// 获取发现列表（分页）
  static Future<PaginatedDiscoveries?> getDiscoveries({
    int page = 1,
    int size = 10,
    String sort = 'time',
    int? type,
    String? search,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'size': '$size',
        'sort': sort,
      };
      if (type != null) {
        params['type'] = '$type';
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      final uri = Uri.parse('$_baseUrl/api/discoveries').replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return PaginatedDiscoveries.fromJson(json);
      }
      return null;
    } catch (e) {
      debugPrint('Get discoveries failed: $e');
      return null;
    }
  }

  /// 随机获取一个发现条目
  static Future<DiscoveryItem?> getRandomDiscovery() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/discoveries/random');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return DiscoveryItem.fromJson(json);
      }
      return null;
    } catch (e) {
      debugPrint('Get random discovery failed: $e');
      return null;
    }
  }

  /// 记录点击
  static Future<void> recordClick(int id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/discoveries/$id/click');
      await http.post(uri).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Record click failed: $e');
    }
  }
}
