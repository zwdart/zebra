class FeedbackItem {
  final int? id;
  final String email;
  final String subject;
  final String description;
  final String platform;
  final String appVersion;
  final String? tags;
  final String? createdAt;

  FeedbackItem({
    this.id,
    required this.email,
    required this.subject,
    required this.description,
    this.platform = '',
    this.appVersion = '',
    this.tags,
    this.createdAt,
  });

  List<String> get tagList {
    if (tags == null || tags!.isEmpty) return [];
    return tags!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      id: json['id'] as int?,
      email: json['email'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      tags: json['tags'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'subject': subject,
      'description': description,
      'platform': platform,
      'app_version': appVersion,
    };
  }
}

class PaginatedFeedback {
  final List<FeedbackItem> items;
  final int total;
  final int page;
  final int size;

  PaginatedFeedback({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  bool get hasMore => page * size < total;

  factory PaginatedFeedback.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>? ?? [];
    return PaginatedFeedback(
      items: data.map((e) => FeedbackItem.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      size: json['size'] as int? ?? 10,
    );
  }
}
