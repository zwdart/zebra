import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/linux_command.dart';
import '../services/update_service.dart';

class LinuxCommandProvider extends ChangeNotifier {
  List<LinuxCommand> _commands = [];
  String _search = '';
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  int _totalCount = 0;
  static const int _pageSize = 20;

  List<LinuxCommand> get commands => _commands;
  String get search => _search;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  int get totalCount => _totalCount;
  int get pageSize => _pageSize;

  Future<void> loadCommands({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _commands = [];
      _hasMore = true;
    }
    _isLoading = true;
    notifyListeners();

    try {
      final params = <String, String>{
        'page': '$_page',
        'size': '$_pageSize',
      };
      if (_search.isNotEmpty) {
        params['search'] = _search;
      }

      final uri = Uri.parse('${UpdateService.apiBaseUrl}/api/linux-commands')
          .replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final total = json['total'] as int? ?? 0;
        final data = json['data'] as List? ?? [];
        final newCommands = data.map((e) => LinuxCommand.fromMap(e)).toList();

        if (refresh) {
          _commands = newCommands;
        } else {
          _commands = [..._commands, ...newCommands];
        }
        _totalCount = total;
        _hasMore = _commands.length < _totalCount;
        _page++;
      }
    } catch (e) {
      debugPrint('Failed to load Linux commands: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void searchCommands(String query) {
    _search = query;
    loadCommands(refresh: true);
  }
}
