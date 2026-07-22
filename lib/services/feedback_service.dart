import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'update_service.dart';

class FeedbackService {
  static String get _baseUrl => UpdateService.apiBaseUrl;

  /// 提交反馈
  static Future<Map<String, dynamic>> submitFeedback({
    required String email,
    required String subject,
    required String description,
    String platform = '',
    String appVersion = '',
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/feedback');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'subject': subject,
          'description': description,
          'platform': platform,
          'app_version': appVersion,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.body.isEmpty) {
        return {'success': false, 'error': '服务器返回了空响应 (HTTP ${response.statusCode})'};
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json;
    } on SocketException {
      return {'success': false, 'error': '无法连接到服务器，请检查网络连接'};
    } on HttpException {
      return {'success': false, 'error': '服务器连接异常，请稍后重试'};
    } on FormatException {
      return {'success': false, 'error': '服务器返回了无效数据，请确认服务器已启动且版本为最新'};
    } on TimeoutException {
      return {'success': false, 'error': '请求超时，请检查网络连接后重试'};
    } catch (e) {
      debugPrint('Submit feedback failed: $e');
      return {'success': false, 'error': '提交失败: $e'};
    }
  }
}
