import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/rss_provider.dart';
import '../../models/rss_article.dart';
import '../../widgets/custom_title_bar.dart';
import 'rss_article_detail_screen.dart';
import 'rss_source_manage_screen.dart';
import 'rss_settings_screen.dart';
import 'rss_folder_manage_screen.dart';
import 'rss_explore_screen.dart';

class RssFeedListScreen extends StatefulWidget {
  const RssFeedListScreen({super.key});

  @override
  State<RssFeedListScreen> createState() => _RssFeedListScreenState();
}

class _RssFeedListScreenState extends State<RssFeedListScreen> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _refreshAnimController;

  @override
  void initState() {
    super.initState();
    _refreshAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<RssProvider>();
      provider.loadFeedSources();
      provider.loadAllArticles(refresh: true);
    });
  }

  @override
  void dispose() {
    _refreshAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _title(RssProvider provider, AppLocalizations loc) {
    switch (provider.viewMode) {
      case ViewMode.all:
        return 'Zebra RSS';
      case ViewMode.starred:
        return loc.rssFavorites;
      case ViewMode.folder:
        return provider.selectedFolderName;
    }
  }

  void _onRefreshTap() {
    _refreshAnimController.forward(from: 0);
    final provider = context.read<RssProvider>();
    switch (provider.viewMode) {
      case ViewMode.all:
        provider.loadAllArticles(refresh: true);
        break;
      case ViewMode.starred:
        provider.loadStarredArticles(refresh: true);
        break;
      case ViewMode.folder:
        if (provider.selectedFolderId != null) {
          provider.loadFolderArticles(provider.selectedFolderId!, refresh: true);
        }
        break;
    }
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
    final provider = context.watch<RssProvider>();

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: GestureDetector(
                onTap: _onRefreshTap,
                child: Text(_title(provider, loc)),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.explore),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RssExploreScreen()),
                  ),
                  tooltip: loc.rssExplore,
                ),
                PopupMenuButton<String>(
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => _buildMenuItems(),
                ),
              ],
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: _title(provider, loc),
              showBackButton: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.explore),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RssExploreScreen()),
                  ),
                  tooltip: loc.rssExplore,
                ),
                PopupMenuButton<String>(
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => _buildMenuItems(),
                ),
              ],
            ),
          _buildFolderChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final loc = AppLocalizations.of(context);
    return [
      // Sync section
      PopupMenuItem(value: 'sync', child: Text(loc.rssSyncAll)),

      const PopupMenuDivider(),

      // Management section
      PopupMenuItem(value: 'manage', child: Text(loc.rssSubscription)),
      PopupMenuItem(value: 'folders', child: Text(loc.rssFolderManagement)),
      PopupMenuItem(value: 'settings', child: Text(loc.settings)),
    ];
  }

  Widget _buildFolderChips() {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    final folders = provider.getAllFolders();

    if (folders.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(loc.discoveryFilterAll),
              selected: provider.viewMode == ViewMode.all,
              onSelected: (_) => provider.switchToAll(),
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(loc.rssFavorites),
              selected: provider.viewMode == ViewMode.starred,
              onSelected: (_) => provider.switchToStarred(),
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              avatar: const Icon(Icons.star, size: 16),
            ),
          ),
          for (final folder in folders)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(folder['name'] as String),
                selected: provider.viewMode == ViewMode.folder && provider.selectedFolderId == folder['id'],
                onSelected: (_) => provider.switchToFolder(folder['id'] as int, folder['name'] as String),
                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                avatar: const Icon(Icons.folder, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<RssProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.articles.isEmpty && provider.feeds.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.feeds.isEmpty && provider.articles.isEmpty) {
          return _buildEmptyState();
        }

        if (provider.articles.isEmpty) {
          return _buildNoArticlesState();
        }

        return RefreshIndicator(
          onRefresh: () async => _onRefreshTap(),
          child: ListView.builder(
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
          ),
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
          Icon(Icons.rss_feed, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(loc.rssNoSources, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(loc.rssAddSourceHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RssSourceManageScreen())),
            icon: const Icon(Icons.add),
            label: Text(loc.rssAddSource),
          ),
        ],
      ),
    );
  }

  Widget _buildNoArticlesState() {
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
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await context.read<RssProvider>().syncAll();
              if (!context.mounted) return;
              _onRefreshTap();
              final error = context.read<RssProvider>().error;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error ?? loc.rssSyncComplete)),
              );
            },
            icon: const Icon(Icons.refresh),
            label: Text(loc.rssSyncNow),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleCard(RssArticle article) {
    final loc = AppLocalizations.of(context);
    final feedTitle = context.read<RssProvider>().getFeedTitle(article.feedSourceId);

    return Dismissible(
      key: ValueKey(article.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                if (feedTitle.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(feedTitle, style: Theme.of(context).textTheme.labelSmall),
                  ),
                  const SizedBox(width: 8),
                ],
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
          trailing: CustomTitleBar.isDesktop
              ? IconButton(
                  icon: Icon(
                    article.isStarred ? Icons.star : Icons.star_border,
                    color: article.isStarred ? Colors.amber : null,
                  ),
                  onPressed: () => context.read<RssProvider>().toggleStar(article.id!),
                )
              : null,
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

  void _handleMenuAction(String action) async {
    final loc = AppLocalizations.of(context);
    switch (action) {
      case 'sync':
        await context.read<RssProvider>().syncAll();
        if (!mounted) return;
        _onRefreshTap();
        final error = context.read<RssProvider>().error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? loc.rssSyncComplete)),
        );
        break;
      case 'starred':
        context.read<RssProvider>().switchToStarred();
        break;
      case 'all':
        context.read<RssProvider>().switchToAll();
        break;
      case 'manage':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RssSourceManageScreen()));
        break;
      case 'explore':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RssExploreScreen()));
        break;
      case 'folders':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RssFolderManageScreen()));
        break;
      case 'settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RssSettingsScreen()));
        break;
    }
  }
}
