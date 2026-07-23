import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/rss_provider.dart';
import '../../models/feed_source.dart';
import '../../models/rss_article.dart';
import '../../widgets/custom_title_bar.dart';
import '../../l10n/app_localizations.dart';
import 'rss_feed_list_screen.dart';
import 'rss_article_detail_screen.dart';

class RssArticleListScreen extends StatefulWidget {
  final FeedSource feedSource;

  const RssArticleListScreen({super.key, required this.feedSource});

  @override
  State<RssArticleListScreen> createState() => _RssArticleListScreenState();
}

class _RssArticleListScreenState extends State<RssArticleListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RssProvider>().loadArticles(widget.feedSource.id!, refresh: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<RssProvider>().loadMoreArticles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(widget.feedSource.title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<RssProvider>().syncFeedSourceById(widget.feedSource.id!),
                  tooltip: loc.rssSyncSource,
                ),
                IconButton(
                  icon: const Icon(Icons.done_all),
                  onPressed: () => _markAllAsRead(),
                  tooltip: loc.rssMarkAllRead,
                ),
                PopupMenuButton<String>(
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'home', child: Text(loc.rssBackToHome)),
                    PopupMenuItem(value: 'clear', child: Text(loc.rssClearArticles)),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: widget.feedSource.title,
              showBackButton: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<RssProvider>().syncFeedSourceById(widget.feedSource.id!),
                  tooltip: loc.rssSyncSource,
                ),
                IconButton(
                  icon: const Icon(Icons.done_all),
                  onPressed: () => _markAllAsRead(),
                  tooltip: loc.rssMarkAllRead,
                ),
                PopupMenuButton<String>(
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'home', child: Text(loc.rssBackToHome)),
                    PopupMenuItem(value: 'clear', child: Text(loc.rssClearArticles)),
                  ],
                ),
              ],
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<RssProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.articles.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.articles.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: provider.articles.length + (provider.hasMoreArticles ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= provider.articles.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final article = provider.articles[index];
            return _buildArticleCard(article);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(loc.rssNoArticles, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(loc.rssNoArticlesHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildArticleCard(RssArticle article) {
    final loc = AppLocalizations.of(context);
    return Dismissible(
      key: ValueKey(article.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(loc.rssDeleteArticle),
            content: Text(loc.rssDeleteArticleConfirm.replaceAll('{title}', article.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(loc.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(loc.delete),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        context.read<RssProvider>().deleteArticle(article.id!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.rssArticleDeleted)),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              article.title.isNotEmpty ? article.title.characters.first : '?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          title: Text(
            article.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: article.isRead ? FontWeight.normal : FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                if (!article.isRead)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(article.displayTime, style: Theme.of(context).textTheme.bodySmall),
                if (article.author.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      article.author.replaceAll(RegExp(r'[\n\r]+'), ' ').trim(),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              article.isStarred ? Icons.star : Icons.star_border,
              color: article.isStarred ? Colors.amber : null,
            ),
            onPressed: () => context.read<RssProvider>().toggleStar(article.id!),
          ),
          onTap: () {
            context.read<RssProvider>().markAsRead(article.id!);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RssArticleDetailScreen(article: article),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'home':
        context.read<RssProvider>().loadAllArticles(refresh: true);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RssFeedListScreen()),
        );
        break;
      case 'clear':
        _confirmClearArticles();
        break;
    }
  }

  void _markAllAsRead() {
    final loc = AppLocalizations.of(context);
    context.read<RssProvider>().markAllAsRead(widget.feedSource.id!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.rssMarkAllReadConfirm)),
    );
  }

  void _confirmClearArticles() {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssClearArticles),
        content: Text(loc.rssClearArticlesConfirm.replaceAll('{name}', widget.feedSource.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<RssProvider>().clearFeedArticles(widget.feedSource.id!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.rssArticlesCleared)),
              );
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }
}
