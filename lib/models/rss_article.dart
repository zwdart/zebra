class RssArticle {
  final int? id;
  final int feedSourceId;
  final String guid;
  final String title;
  final String link;
  final String author;
  final String summary;
  final String content;
  final String? publishedAt;
  final bool isRead;
  final bool isStarred;
  final String? createdAt;

  RssArticle({
    this.id,
    required this.feedSourceId,
    this.guid = '',
    required this.title,
    this.link = '',
    this.author = '',
    this.summary = '',
    this.content = '',
    this.publishedAt,
    this.isRead = false,
    this.isStarred = false,
    this.createdAt,
  });

  RssArticle copyWith({
    int? id,
    int? feedSourceId,
    String? guid,
    String? title,
    String? link,
    String? author,
    String? summary,
    String? content,
    String? publishedAt,
    bool? isRead,
    bool? isStarred,
    String? createdAt,
  }) {
    return RssArticle(
      id: id ?? this.id,
      feedSourceId: feedSourceId ?? this.feedSourceId,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      link: link ?? this.link,
      author: author ?? this.author,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      publishedAt: publishedAt ?? this.publishedAt,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory RssArticle.fromMap(Map<String, dynamic> map) {
    return RssArticle(
      id: map['id'] as int?,
      feedSourceId: map['feed_source_id'] as int? ?? 0,
      guid: map['guid'] as String? ?? '',
      title: map['title'] as String? ?? '',
      link: map['link'] as String? ?? '',
      author: map['author'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      content: map['content'] as String? ?? '',
      publishedAt: map['published_at'] as String?,
      isRead: (map['is_read'] as int? ?? 0) == 1,
      isStarred: (map['is_starred'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'feed_source_id': feedSourceId,
      'guid': guid,
      'title': title,
      'link': link,
      'author': author,
      'summary': summary,
      'content': content,
      'published_at': publishedAt,
      'is_read': isRead ? 1 : 0,
      'is_starred': isStarred ? 1 : 0,
      'created_at': createdAt,
    };
  }

  DateTime? get publishedDateTime {
    if (publishedAt == null || publishedAt!.isEmpty) return null;
    // Try ISO 8601 first
    final iso = DateTime.tryParse(publishedAt!);
    if (iso != null) return iso;
    // Try RFC 822 format (common in RSS feeds)
    return _parseRfc822(publishedAt!);
  }

  static DateTime? _parseRfc822(String dateStr) {
    try {
      // RFC 822: "Mon, 21 Jul 2026 12:00:00 +0800"
      // Remove day name prefix if present
      var s = dateStr.trim();
      if (s.contains(',') && s.length > 4) {
        s = s.substring(s.indexOf(',') + 1).trim();
      }
      // Parse: "21 Jul 2026 12:00:00 +0800"
      final months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
      };
      final parts = s.split(RegExp(r'\s+'));
      if (parts.length < 4) return null;
      final day = int.parse(parts[0]);
      final month = months[parts[1]] ?? 1;
      final year = int.parse(parts[2]);
      final timeParts = parts[3].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts.length > 1 ? timeParts[1] : '0');
      final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;

      // Parse timezone offset
      int offsetHours = 0;
      int offsetMinutes = 0;
      if (parts.length > 4) {
        final tz = parts[4];
        if (tz == 'Z' || tz == 'GMT') {
          // UTC
        } else if (tz.startsWith('+') || tz.startsWith('-')) {
          final sign = tz[0] == '-' ? -1 : 1;
          final tzDigits = tz.substring(1);
          if (tzDigits.length >= 4) {
            offsetHours = sign * int.parse(tzDigits.substring(0, 2));
            offsetMinutes = sign * int.parse(tzDigits.substring(2, 4));
          }
        }
      }

      final utc = DateTime.utc(year, month, day, hour, minute, second);
      return utc.subtract(Duration(hours: offsetHours, minutes: offsetMinutes));
    } catch (_) {
      return null;
    }
  }

  String get displayTime {
    return publishedAt ?? '';
  }
}
