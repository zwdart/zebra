import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/blog_post.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';

class BlogDetailScreen extends StatelessWidget {
  final BlogPost post;

  const BlogDetailScreen({super.key, required this.post});

  String _getDetailUrl() {
    return '${UpdateService.apiBaseUrl}/api/blog/post/${post.id}';
  }

  String _formatDate(String? s) {
    if (s == null || s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _shareLink() {
    final url = _getDetailUrl();
    Share.share('${post.title}\n$url');
  }

  void _openInBrowser() {
    launchUrl(Uri.parse(_getDetailUrl()), mode: LaunchMode.externalApplication);
  }

  void _copyLink(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final url = _getDetailUrl();
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.linkCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    final htmlContent = md.markdownToHtml(
      post.content,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );

    return Scaffold(
      appBar: CustomTitleBar.isDesktop
          ? null
          : AppBar(
              title: Text(
                post.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'share':
                        _shareLink();
                        break;
                      case 'browser':
                        _openInBrowser();
                        break;
                      case 'copy':
                        _copyLink(context);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'share', child: Text(loc.share)),
                    PopupMenuItem(value: 'browser', child: Text(loc.openInBrowser)),
                    PopupMenuItem(value: 'copy', child: Text(loc.copyLink)),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: post.title,
              showBackButton: true,
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onSelected: (value) {
                    switch (value) {
                      case 'share':
                        _shareLink();
                        break;
                      case 'browser':
                        _openInBrowser();
                        break;
                      case 'copy':
                        _copyLink(context);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'share', child: Text(loc.share)),
                    PopupMenuItem(value: 'browser', child: Text(loc.openInBrowser)),
                    PopupMenuItem(value: 'copy', child: Text(loc.copyLink)),
                  ],
                ),
              ],
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  post.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(post.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                if (post.tagList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: post.tagList.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                SelectionArea(
                  child: Html(
                  data: htmlContent,
                  style: {
                    "body": Style(
                      fontSize: FontSize(15),
                      lineHeight: LineHeight(1.8),
                    ),
                    "h1": Style(
                      fontSize: FontSize(24),
                      fontWeight: FontWeight.bold,
                    ),
                    "h2": Style(
                      fontSize: FontSize(20),
                      fontWeight: FontWeight.bold,
                    ),
                    "h3": Style(
                      fontSize: FontSize(17),
                      fontWeight: FontWeight.bold,
                    ),
                    "a": Style(
                      color: theme.colorScheme.primary,
                    ),
                    "pre": Style(
                      backgroundColor: const Color(0xFF1a1a2e),
                      color: const Color(0xFFe8e8e8),
                      padding: HtmlPaddings.all(16),
                    ),
                    "code": Style(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      padding: HtmlPaddings.symmetric(horizontal: 4, vertical: 2),
                      fontFamily: 'monospace',
                      fontSize: FontSize(13),
                    ),
                    "pre code": Style(
                      backgroundColor: Colors.transparent,
                      padding: HtmlPaddings.zero,
                      color: const Color(0xFFe8e8e8),
                    ),
                    "blockquote": Style(
                      border: Border(
                        left: BorderSide(color: theme.colorScheme.primary, width: 4),
                      ),
                      padding: HtmlPaddings.symmetric(horizontal: 16, vertical: 8),
                      backgroundColor: theme.colorScheme.surfaceContainerLow,
                    ),
                    "img": Style(
                      width: Width(100, Unit.percent),
                    ),
                    "table": Style(
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                    ),
                    "th": Style(
                      backgroundColor: theme.colorScheme.surfaceContainerLow,
                      padding: HtmlPaddings.all(8),
                    ),
                    "td": Style(
                      padding: HtmlPaddings.all(8),
                    ),
                    "hr": Style(
                      border: Border(
                        bottom: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                      ),
                    ),
                  },
                  onLinkTap: (url, attributes, element) {
                    if (url != null) {
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
