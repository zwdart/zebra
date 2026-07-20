class DiscoveryItem {
  final int? id;
  final int type; // 0=官方, 1=推荐, 2=广告
  final String name;
  final String description;
  final String url;
  final String? iconUrl;
  final String? tags;
  final int clicks;
  final int sortOrder;
  final bool enabled;
  final String? createdAt;
  final String? updatedAt;

  DiscoveryItem({
    this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.url,
    this.iconUrl,
    this.tags,
    this.clicks = 0,
    this.sortOrder = 0,
    this.enabled = true,
    this.createdAt,
    this.updatedAt,
  });

  List<String> get tagList {
    if (tags == null || tags!.isEmpty) return [];
    return tags!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  String get typeName {
    switch (type) {
      case 0:
        return 'Official';
      case 1:
        return 'Recommended';
      case 2:
        return 'Ad';
      default:
        return 'Unknown';
    }
  }

  factory DiscoveryItem.fromJson(Map<String, dynamic> json) {
    return DiscoveryItem(
      id: json['id'] as int?,
      type: json['type'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      url: json['url'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      tags: json['tags'] as String?,
      clicks: json['clicks'] as int? ?? 0,
      sortOrder: json['sort_order'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'name': name,
      'description': description,
      'url': url,
      'icon_url': iconUrl,
      'tags': tags,
      'sort_order': sortOrder,
      'enabled': enabled,
    };
  }
}

class PaginatedDiscoveries {
  final List<DiscoveryItem> items;
  final int total;
  final int page;
  final int size;

  PaginatedDiscoveries({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  bool get hasMore => page * size < total;

  factory PaginatedDiscoveries.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>? ?? [];
    return PaginatedDiscoveries(
      items: data.map((e) => DiscoveryItem.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      size: json['size'] as int? ?? 10,
    );
  }
}
