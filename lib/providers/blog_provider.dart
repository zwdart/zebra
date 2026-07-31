import 'package:flutter/foundation.dart';
import '../models/blog_post.dart';
import '../services/blog_service.dart';

/// 博客列表状态管理
class BlogProvider extends ChangeNotifier {
  final List<BlogPost> _items = [];
  bool _isLoading = false;
  int _currentPage = 1;
  int _total = 0;
  final int _pageSize = 10;

  List<BlogPost> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  int get currentPage => _currentPage;
  int get total => _total;
  int get pageSize => _pageSize;
  int get totalPages => (_total / _pageSize).ceil().clamp(1, 9999);
  bool get hasMore => _items.length < _total;

  /// 加载数据
  Future<void> loadData({bool refresh = false}) async {
    if (_isLoading) return;
    if (refresh) {
      _currentPage = 1;
      _items.clear();
    }

    _isLoading = true;
    notifyListeners();

    final result = await BlogService.getBlogPosts(
      page: _currentPage,
      size: _pageSize,
    );

    _isLoading = false;
    if (result != null) {
      if (refresh) _items.clear();
      _items.addAll(result.items);
      _total = result.total;
    }
    notifyListeners();
  }

  /// 加载更多（滚动加载）
  void loadMore() {
    if (_isLoading || !hasMore) return;
    _currentPage++;
    loadData();
  }

  /// 跳转到指定页
  void goToPage(int page) {
    final target = page.clamp(1, totalPages);
    if (target != _currentPage) {
      _currentPage = target;
      loadData(refresh: true);
    }
  }
}
