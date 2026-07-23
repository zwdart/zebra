import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Simulates the RSS 2.0 parsing logic from rss_repository.dart
List<Map<String, String>> parseRss2(String xmlString) {
  final document = XmlDocument.parse(xmlString);
  final articles = <Map<String, String>>[];
  final items = document.findAllElements('item');
  for (final item in items) {
    final title = item.findElements('title').firstOrNull?.innerText.trim() ?? '';
    final pubDate = item.findElements('pubDate').firstOrNull?.innerText.trim() ?? '';
    articles.add({'title': title, 'publishedAt': pubDate});
  }
  return articles;
}

void main() {
  // Simulate an RSS feed where item[0] is newest, item[last] is oldest
  const rssXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
  <title>Test Feed</title>
  <item>
    <title>Article 1 - Newest (Jul 22)</title>
    <pubDate>Tue, 22 Jul 2026 10:00:00 +0800</pubDate>
  </item>
  <item>
    <title>Article 2 - Middle (Jul 21)</title>
    <pubDate>Mon, 21 Jul 2026 10:00:00 +0800</pubDate>
  </item>
  <item>
    <title>Article 3 - Oldest (Jul 20)</title>
    <pubDate>Sun, 20 Jul 2026 10:00:00 +0800</pubDate>
  </item>
</channel>
</rss>''';

  test('RSS parsing returns newest-first order (document order)', () {
    final articles = parseRss2(rssXml);
    expect(articles.length, 3);
    expect(articles[0]['title'], contains('Newest'));
    expect(articles[1]['title'], contains('Middle'));
    expect(articles[2]['title'], contains('Oldest'));
  });

  test('After .reversed, oldest comes first for insertion', () {
    final articles = parseRss2(rssXml).reversed.toList();
    expect(articles.length, 3);
    // After reversal: oldest first → gets smallest ID
    expect(articles[0]['title'], contains('Oldest'));
    expect(articles[1]['title'], contains('Middle'));
    expect(articles[2]['title'], contains('Newest'));
  });

  test('Simulated DB insert order: oldest gets small ID, newest gets large ID', () {
    final articles = parseRss2(rssXml).reversed.toList();
    final dbInsertOrder = <String, int>{};

    // Simulate auto-increment ID
    var nextId = 1;
    for (final article in articles) {
      dbInsertOrder[article['title']!] = nextId++;
    }

    // Newest article should have the largest ID
    final newestEntry = dbInsertOrder.entries.firstWhere((e) => e.key.contains('Newest'));
    final oldestEntry = dbInsertOrder.entries.firstWhere((e) => e.key.contains('Oldest'));

    expect(newestEntry.value, greaterThan(oldestEntry.value));

    // When queried with ORDER BY id DESC, newest comes first
    final sortedByDescId = dbInsertOrder.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    expect(sortedByDescId.first.key, contains('Newest'));
    expect(sortedByDescId.last.key, contains('Oldest'));
  });
}
