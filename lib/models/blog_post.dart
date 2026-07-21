class BlogPost {
  final int? id;
  final String title;
  final String content;
  final String summary;
  final String? tags;
  final int sortOrder;
  final bool published;
  final String? createdAt;
  final String? updatedAt;

  BlogPost({
    this.id,
    required this.title,
    required this.content,
    this.summary = '',
    this.tags,
    this.sortOrder = 0,
    this.published = true,
    this.createdAt,
    this.updatedAt,
  });

  List<String> get tagList {
    if (tags == null || tags!.isEmpty) return [];
    return tags!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  factory BlogPost.fromJson(Map<String, dynamic> json) {
    return BlogPost(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      tags: json['tags'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      published: json['published'] as bool? ?? true,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'summary': summary,
      'tags': tags,
      'sort_order': sortOrder,
      'published': published,
    };
  }
}

class PaginatedBlogPosts {
  final List<BlogPost> items;
  final int total;
  final int page;
  final int size;

  PaginatedBlogPosts({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  bool get hasMore => page * size < total;

  factory PaginatedBlogPosts.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>? ?? [];
    return PaginatedBlogPosts(
      items: data.map((e) => BlogPost.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      size: json['size'] as int? ?? 10,
    );
  }
}
