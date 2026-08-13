class FeedSource {
  final int? id;
  final String title;
  final String url;
  final String siteUrl;
  final String feedType; // rss1, rss2, atom
  final String iconUrl;
  final String category;
  final String? lastSyncedAt;
  final bool syncEnabled;
  final bool fetchEnabled;
  final int sortOrder;
  final String source; // local, server
  final String? createdAt;
  final String? updatedAt;
  final String? lastSyncError;

  FeedSource({
    this.id,
    required this.title,
    required this.url,
    this.siteUrl = '',
    this.feedType = 'rss2',
    this.iconUrl = '',
    this.category = '',
    this.lastSyncedAt,
    this.syncEnabled = true,
    this.fetchEnabled = true,
    this.sortOrder = 0,
    this.source = 'local',
    this.createdAt,
    this.updatedAt,
    this.lastSyncError,
  });

  FeedSource copyWith({
    int? id,
    String? title,
    String? url,
    String? siteUrl,
    String? feedType,
    String? iconUrl,
    String? category,
    String? lastSyncedAt,
    bool? syncEnabled,
    bool? fetchEnabled,
    int? sortOrder,
    String? source,
    String? createdAt,
    String? updatedAt,
    String? lastSyncError,
  }) {
    return FeedSource(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      siteUrl: siteUrl ?? this.siteUrl,
      feedType: feedType ?? this.feedType,
      iconUrl: iconUrl ?? this.iconUrl,
      category: category ?? this.category,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      fetchEnabled: fetchEnabled ?? this.fetchEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSyncError: lastSyncError ?? this.lastSyncError,
    );
  }

  String get feedTypeLabel {
    switch (feedType) {
      case 'rss1':
        return 'RSS 1.0';
      case 'rss2':
        return 'RSS 2.0';
      case 'atom':
        return 'Atom';
      default:
        return feedType;
    }
  }

  factory FeedSource.fromMap(Map<String, dynamic> map) {
    return FeedSource(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      url: map['url'] as String? ?? '',
      siteUrl: map['site_url'] as String? ?? '',
      feedType: map['feed_type'] as String? ?? 'rss2',
      iconUrl: map['icon_url'] as String? ?? '',
      category: map['category'] as String? ?? '',
      lastSyncedAt: map['last_synced_at'] as String?,
      syncEnabled: (map['sync_enabled'] as int? ?? 1) == 1,
      fetchEnabled: (map['fetch_enabled'] as int? ?? 1) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
      source: map['source'] as String? ?? 'local',
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
      lastSyncError: map['last_sync_error'] as String?,
    );
  }

  factory FeedSource.fromJson(Map<String, dynamic> json) {
    return FeedSource(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      siteUrl: json['site_url'] as String? ?? '',
      feedType: json['feed_type'] as String? ?? 'rss2',
      iconUrl: json['icon_url'] as String? ?? '',
      category: json['category'] as String? ?? '',
      lastSyncedAt: json['last_synced_at'] as String?,
      syncEnabled: json['sync_enabled'] as bool? ?? true,
      fetchEnabled: json['fetch_enabled'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      source: json['source'] as String? ?? 'local',
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      lastSyncError: json['last_sync_error'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'url': url,
      'site_url': siteUrl,
      'feed_type': feedType,
      'icon_url': iconUrl,
      'category': category,
      'last_synced_at': lastSyncedAt,
      'sync_enabled': syncEnabled ? 1 : 0,
      'fetch_enabled': fetchEnabled ? 1 : 0,
      'sort_order': sortOrder,
      'source': source,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_sync_error': lastSyncError,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'site_url': siteUrl,
      'feed_type': feedType,
      'icon_url': iconUrl,
      'category': category,
      'sync_enabled': syncEnabled,
      'fetch_enabled': fetchEnabled,
      'sort_order': sortOrder,
      'source': source,
      'last_sync_error': lastSyncError,
    };
  }
}
