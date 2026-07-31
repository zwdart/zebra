import 'package:flutter/foundation.dart';
import '../models/discovery_item.dart';
import '../services/discovery_service.dart';

/// 发现页面状态管理
class DiscoveryProvider extends ChangeNotifier {
  final List<DiscoveryItem> _items = [];
  bool _isLoading = false;
  int _currentPage = 1;
  int _total = 0;
  final int _pageSize = 10;
  String _sort = 'order';
  int? _filterType;

  List<DiscoveryItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  int get currentPage => _currentPage;
  int get total => _total;
  int get pageSize => _pageSize;
  int get totalPages => (_total / _pageSize).ceil().clamp(1, 9999);
  String get sortMode => _sort;
  int? get filterType => _filterType;
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

    final result = await DiscoveryService.getDiscoveries(
      page: _currentPage,
      size: _pageSize,
      sort: _sort,
      type: _filterType,
    );

    _isLoading = false;
    if (result != null) {
      if (refresh) _items.clear();
      final newItems = List<DiscoveryItem>.from(result.items);
      if (_sort == 'order') {
        newItems.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      _items.clear();
      _items.addAll(newItems);
      _total = result.total;
    }
    notifyListeners();
  }

  /// 切换排序
  void toggleSort() {
    if (_sort == 'order') {
      _sort = 'time';
    } else if (_sort == 'time') {
      _sort = 'hot';
    } else {
      _sort = 'order';
    }
    loadData(refresh: true);
  }

  /// 设置筛选类型
  void setFilterType(int? type) {
    _filterType = type;
    loadData(refresh: true);
  }

  /// 跳转到指定页
  void goToPage(int page) {
    final target = page.clamp(1, totalPages);
    if (target != _currentPage) {
      _currentPage = target;
      loadData();
    }
  }
}
