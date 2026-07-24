import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/rss_article.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/rss_provider.dart';
import '../../widgets/custom_title_bar.dart';

enum ContentDisplayMode { hidden, rendered, raw }
enum SummaryDisplayMode { raw, rendered }

class RssArticleDetailScreen extends StatefulWidget {
  final RssArticle article;

  const RssArticleDetailScreen({super.key, required this.article});

  @override
  State<RssArticleDetailScreen> createState() => _RssArticleDetailScreenState();
}

class _RssArticleDetailScreenState extends State<RssArticleDetailScreen> {
  ContentDisplayMode _contentMode = ContentDisplayMode.hidden;
  SummaryDisplayMode? _summaryMode; // null = not yet detected (waiting for full article)
  bool _htmlReady = false;
  bool _summaryExpanded = false;
  bool _contentExpanded = false;
  bool _summaryModeDetected = false;
  bool _isStarred = false;

  // Cached built widgets to avoid re-parsing HTML on setState.
  Widget? _cachedSummaryHtml;
  String? _cachedSummaryData;
  Widget? _cachedContentHtml;
  String? _cachedContentData;

  RssArticle get article => widget.article;

  @override
  void initState() {
    super.initState();
    // Defer HTML parsing to after the first frame paints, so the page
    // opens instantly with plain text while flutter_html parses in the
    // background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _htmlReady = true);
    });
  }

  SummaryDisplayMode _detectSummaryMode(String text) {
    if (text.isEmpty) return SummaryDisplayMode.raw;
    final htmlPattern = RegExp(r'<[a-zA-Z][^>]*>|&[a-zA-Z]+;|<!DOCTYPE', caseSensitive: false);
    return htmlPattern.hasMatch(text) ? SummaryDisplayMode.rendered : SummaryDisplayMode.raw;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(article.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: Icon(
                    _isStarred ? Icons.star : Icons.star_border,
                    color: _isStarred ? Colors.amber : null,
                  ),
                  onPressed: () => _toggleStar(context),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) => _handleAction(context, action),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'copy', child: Text(loc.rssCopyLink)),
                    PopupMenuItem(value: 'share', child: Text(loc.share)),
                    PopupMenuItem(
                      value: 'read',
                      child: Text(article.isRead ? loc.rssMarkAsUnread : loc.rssMarkAsRead),
                    ),
                    if (article.link.isNotEmpty)
                      PopupMenuItem(value: 'browser', child: Text(loc.rssViewInBrowser)),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: article.title,
              showBackButton: true,
              actions: [
                IconButton(
                  icon: Icon(
                    _isStarred ? Icons.star : Icons.star_border,
                    color: _isStarred ? Colors.amber : null,
                    size: 18,
                  ),
                  onPressed: () => _toggleStar(context),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) => _handleAction(context, action),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'copy', child: Text(loc.rssCopyLink)),
                    PopupMenuItem(value: 'share', child: Text(loc.share)),
                    PopupMenuItem(
                      value: 'read',
                      child: Text(article.isRead ? loc.rssMarkAsUnread : loc.rssMarkAsRead),
                    ),
                    if (article.link.isNotEmpty)
                      PopupMenuItem(value: 'browser', child: Text(loc.rssViewInBrowser)),
                  ],
                ),
              ],
            ),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    // Lazy-load full article from DB so list queries stay lightweight.
    return FutureBuilder<RssArticle?>(
      future: _loadFullArticle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton(context);
        }
        final fullArticle = snapshot.data ?? article;
        return _buildArticleBody(context, fullArticle, isWide);
      },
    );
  }

  Future<RssArticle?>? _fullArticleFuture;

  Future<RssArticle?> _loadFullArticle() {
    _fullArticleFuture ??= Future(() async {
      // Yield to let the first frame paint (skeleton shows).
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return article;
      final provider = context.read<RssProvider>();
      final full = provider.getArticle(article.id!);
      final result = full ?? article;
      if (mounted) _isStarred = result.isStarred;
      return result;
    });
    return _fullArticleFuture!;
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title skeleton
              Container(
                height: 24,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              // Author/time skeleton
              Container(
                height: 14,
                width: 200,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              // Buttons skeleton
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Summary skeleton lines
              ...List.generate(4, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: 14,
                  width: i == 3 ? 180 : double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArticleBody(BuildContext context, RssArticle fullArticle, bool isWide) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);

    // Detect summary mode from full article (first time only).
    if (!_summaryModeDetected) {
      _summaryModeDetected = true;
      _summaryMode = _detectSummaryMode(fullArticle.summary);
    }

    return SelectionArea(
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                fullArticle.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),

              // Author & time
              if (fullArticle.author.isNotEmpty || fullArticle.displayTime.isNotEmpty)
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (fullArticle.author.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline, size: 16, color: theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(fullArticle.author, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                        ],
                      ),
                    if (fullArticle.displayTime.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time, size: 16, color: theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(fullArticle.displayTime, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                        ],
                      ),
                  ],
                ),
              const SizedBox(height: 16),

              // Summary
              if (fullArticle.summary.isNotEmpty && _summaryMode != null) ...[
                Center(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(loc.rssOriginal),
                        selected: _summaryMode == SummaryDisplayMode.raw,
                        onSelected: (_) => setState(() {
                          _summaryMode = SummaryDisplayMode.raw;
                          _summaryExpanded = false;
                        }),
                        avatar: Icon(
                          _summaryMode == SummaryDisplayMode.raw ? Icons.text_fields : Icons.text_fields_outlined,
                          size: 16,
                        ),
                      ),
                      ChoiceChip(
                        label: Text(loc.rssRendered),
                        selected: _summaryMode == SummaryDisplayMode.rendered,
                        onSelected: (_) => setState(() {
                          _summaryMode = SummaryDisplayMode.rendered;
                          _summaryExpanded = false;
                          // Invalidate cached HTML so it rebuilds with current theme.
                          _cachedSummaryHtml = null;
                        }),
                        avatar: Icon(
                          _summaryMode == SummaryDisplayMode.rendered ? Icons.html : Icons.html_outlined,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _summaryMode == SummaryDisplayMode.rendered && _htmlReady
                    ? _buildSummaryHtml(context, fullArticle)
                    : _buildSummaryText(context, fullArticle),
                const SizedBox(height: 20),
              ],

              // Content toggle
              if (fullArticle.content.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: 12),
                // Mode selector chips
                Center(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(loc.rssHidden),
                        selected: _contentMode == ContentDisplayMode.hidden,
                        onSelected: (_) => setState(() => _contentMode = ContentDisplayMode.hidden),
                        avatar: Icon(
                          _contentMode == ContentDisplayMode.hidden ? Icons.visibility_off : Icons.visibility_off_outlined,
                          size: 16,
                        ),
                      ),
                      ChoiceChip(
                        label: Text(loc.rssRendered),
                        selected: _contentMode == ContentDisplayMode.rendered,
                        onSelected: (_) => setState(() {
                          _contentMode = ContentDisplayMode.rendered;
                          _contentExpanded = false;
                          // Invalidate cached HTML.
                          _cachedContentHtml = null;
                        }),
                        avatar: Icon(
                          _contentMode == ContentDisplayMode.rendered ? Icons.html : Icons.html_outlined,
                          size: 16,
                        ),
                      ),
                      ChoiceChip(
                        label: Text(loc.rssOriginal),
                        selected: _contentMode == ContentDisplayMode.raw,
                        onSelected: (_) => setState(() {
                          _contentMode = ContentDisplayMode.raw;
                          _contentExpanded = false;
                        }),
                        avatar: Icon(
                          _contentMode == ContentDisplayMode.raw ? Icons.code : Icons.code_outlined,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_contentMode == ContentDisplayMode.hidden)
                  const SizedBox.shrink()
                else if (_contentMode == ContentDisplayMode.rendered && _htmlReady)
                  _buildContentHtml(context, fullArticle)
                else
                  _buildContentRaw(context, fullArticle),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }

  // ==================== Summary builders ====================

  Widget _buildSummaryHtml(BuildContext context, RssArticle fullArticle) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isLong = fullArticle.summary.length > 800;
    final displayText = isLong && !_summaryExpanded
        ? fullArticle.summary.substring(0, 800)
        : fullArticle.summary;

    // Cache the Html widget to avoid re-parsing on setState.
    if (_cachedSummaryHtml == null || _cachedSummaryData != displayText) {
      _cachedSummaryData = displayText;
      _cachedSummaryHtml = RepaintBoundary(
        child: Html(
          data: displayText,
          style: {
            'body': Style(
              fontSize: FontSize.medium,
              lineHeight: const LineHeight(1.6),
            ),
            'img': Style(
              width: Width.auto(),
              display: Display.block,
              margin: Margins.symmetric(vertical: 8),
            ),
            'a': Style(color: theme.colorScheme.primary),
          },
          onLinkTap: (url, attributes, element) {
            if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          extensions: [
            TagExtension(
              tagsToExtend: {'img'},
              builder: (extensionContext) {
                final src = extensionContext.attributes['src'] ?? '';
                if (src.isEmpty) return const SizedBox.shrink();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    src,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, color: theme.colorScheme.error, size: 16),
                          const SizedBox(width: 8),
                          Text(loc.imageLoadFailed, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
                        ],
                      ),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _cachedSummaryHtml!,
        ),
        if (isLong)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _summaryExpanded = !_summaryExpanded;
                _cachedSummaryHtml = null; // invalidate to rebuild with full text
              }),
              child: Text(
                _summaryExpanded ? loc.rssCollapse : loc.rssExpand,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryText(BuildContext context, RssArticle fullArticle) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isLong = fullArticle.summary.length > 800;
    final displayText = isLong && !_summaryExpanded
        ? fullArticle.summary.substring(0, 800)
        : fullArticle.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayText, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _summaryExpanded ? loc.rssCollapse : loc.rssExpand,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ==================== Content builders ====================

  Widget _buildContentHtml(BuildContext context, RssArticle fullArticle) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isLong = fullArticle.content.length > 2000;
    final displayText = isLong && !_contentExpanded
        ? fullArticle.content.substring(0, 2000)
        : fullArticle.content;

    // Cache the Html widget.
    if (_cachedContentHtml == null || _cachedContentData != displayText) {
      _cachedContentData = displayText;
      _cachedContentHtml = RepaintBoundary(
        child: Html(
          data: displayText,
          style: {
            'body': Style(
              fontSize: FontSize.medium,
              lineHeight: const LineHeight(1.6),
            ),
            'img': Style(
              width: Width.auto(),
              display: Display.block,
              margin: Margins.symmetric(vertical: 8),
            ),
            'a': Style(color: theme.colorScheme.primary),
          },
          onLinkTap: (url, attributes, element) {
            if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          extensions: [
            TagExtension(
              tagsToExtend: {'img'},
              builder: (extensionContext) {
                final src = extensionContext.attributes['src'] ?? '';
                if (src.isEmpty) return const SizedBox.shrink();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    src,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, color: theme.colorScheme.error, size: 16),
                          const SizedBox(width: 8),
                          Text(loc.imageLoadFailed, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
                        ],
                      ),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _cachedContentHtml!,
        ),
        if (isLong)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _contentExpanded = !_contentExpanded;
                _cachedContentHtml = null;
              }),
              child: Text(
                _contentExpanded ? loc.rssCollapse : loc.rssExpand,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContentRaw(BuildContext context, RssArticle fullArticle) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isLong = fullArticle.content.length > 2000;
    final displayText = isLong && !_contentExpanded
        ? fullArticle.content.substring(0, 2000)
        : fullArticle.content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            displayText,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
        if (isLong)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() => _contentExpanded = !_contentExpanded),
              child: Text(
                _contentExpanded ? loc.rssCollapse : loc.rssExpand,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openInBrowser(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    if (article.link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssNoLink)),
      );
      return;
    }
    final uri = Uri.parse(article.link);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _toggleStar(BuildContext context) {
    context.read<RssProvider>().toggleStar(article.id!);
    setState(() => _isStarred = !_isStarred);
  }

  void _handleAction(BuildContext context, String action) {
    final loc = AppLocalizations.of(context);
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: article.link));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.rssLinkCopied)),
        );
        break;
      case 'share':
        Share.share('${article.title}\n${article.link}');
        break;
      case 'read':
        context.read<RssProvider>().markAsRead(article.id!);
        break;
      case 'browser':
        _openInBrowser(context);
        break;
    }
  }
}
