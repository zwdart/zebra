import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // 快捷键选中项（三栏模式：J/K 上下移动、R 已读、S 星标）
  final FocusNode _listFocusNode = FocusNode();
  int _selectedIndex = -1;
  RssArticle? _previewArticle;

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
    _listFocusNode.dispose();
    _refreshAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isWide => MediaQuery.sizeOf(context).width > 1000;

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
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyJ): _onKeyDown,
          const SingleActivator(LogicalKeyboardKey.keyK): _onKeyUp,
          const SingleActivator(LogicalKeyboardKey.keyR): _onKeyRead,
          const SingleActivator(LogicalKeyboardKey.keyS): _onKeyStar,
        },
        child: Focus(
          focusNode: _listFocusNode,
          autofocus: true,
          child: Column(
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
              if (_isWide)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSideNav(provider),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            _buildFolderChips(),
                            Expanded(child: _buildBody()),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      _buildPreviewPane(provider),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      _buildFolderChips(),
                      Expanded(child: _buildBody()),
                    ],
                  ),
                ),
            ],
          ),
        ),
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

  // ==================== 快捷键处理 ====================

  void _moveSelection(int delta) {
    final provider = context.read<RssProvider>();
    if (provider.articles.isEmpty) return;
    final next = (_selectedIndex + delta).clamp(0, provider.articles.length - 1);
    setState(() {
      _selectedIndex = next;
      _previewArticle = provider.articles[next];
    });
    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (_selectedIndex < 0 || !_scrollController.hasClients) return;
    final offset = (_selectedIndex * 76.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _onKeyDown() => _moveSelection(1);
  void _onKeyUp() => _moveSelection(-1);

  void _onKeyRead() {
    final provider = context.read<RssProvider>();
    if (_selectedIndex < 0 || _selectedIndex >= provider.articles.length) return;
    final a = provider.articles[_selectedIndex];
    if (!a.isRead) provider.markAsRead(a.id!);
  }

  void _onKeyStar() {
    final provider = context.read<RssProvider>();
    if (_selectedIndex < 0 || _selectedIndex >= provider.articles.length) return;
    provider.toggleStar(provider.articles[_selectedIndex].id!);
  }

  // ==================== 三栏布局（宽屏） ====================

  Widget _buildSideNav(RssProvider provider) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sources = provider.feeds;

    return Container(
      width: 220,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              loc.rssSubscription,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.article_outlined, size: 20),
                title: Text(loc.discoveryFilterAll),
                trailing: _UnreadBadge(count: provider.totalUnreadCount),
                selected: provider.viewMode == ViewMode.all && provider.currentFeed == null,
                onTap: () => provider.switchToAll(),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.star_border, size: 20),
                title: Text(loc.rssFavorites),
                selected: provider.viewMode == ViewMode.starred,
                onTap: () => provider.switchToStarred(),
              ),
              const Divider(height: 8),
              for (final folder in provider.getAllFolders())
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined, size: 20),
                  title: Text(folder['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                  selected: provider.viewMode == ViewMode.folder && provider.selectedFolderId == folder['id'],
                  onTap: () => provider.switchToFolder(folder['id'] as int, folder['name'] as String),
                ),
              const Divider(height: 8),
              for (final source in sources)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.rss_feed, size: 20),
                  title: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: _UnreadBadge(count: provider.getUnreadCountForFeed(source.id ?? -1)),
                  selected: provider.currentFeed?.id == source.id,
                  onTap: () => provider.loadArticles(source.id!, refresh: true),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPane(RssProvider provider) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final article = _previewArticle;

    return Container(
      width: 340,
      color: theme.colorScheme.surfaceContainerLow,
      child: article == null
          ? Center(
              child: Text(
                loc.rssSelectArticleHint,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.displayTime,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  if (article.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(article.author, style: theme.textTheme.bodySmall),
                  ],
                  const Divider(height: 24),
                  if (article.summary.isNotEmpty)
                    Text(
                      article.summary.replaceAll(RegExp(r'<[^>]+>'), ''),
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => _openArticle(article),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(loc.rssOpenArticle),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          article.isStarred ? Icons.star : Icons.star_border,
                          color: article.isStarred ? Colors.amber : null,
                        ),
                        onPressed: () => context.read<RssProvider>().toggleStar(article.id!),
                      ),
                      IconButton(
                        icon: const Icon(Icons.done, size: 18),
                        tooltip: loc.rssMarkAsRead,
                        onPressed: () => context.read<RssProvider>().markAsRead(article.id!),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  void _openArticle(RssArticle article) {
    final provider = context.read<RssProvider>();
    if (!article.isRead) provider.markAsRead(article.id!);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RssArticleDetailScreen(article: article)),
    );
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
              return _buildArticleCard(article, selected: index == _selectedIndex);
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

  Widget _buildArticleCard(RssArticle article, {bool selected = false}) {
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
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
              )
            : null,
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
            final provider = context.read<RssProvider>();
            if (!article.isRead) provider.markAsRead(article.id!);
            if (_isWide) {
              setState(() {
                _selectedIndex = provider.articles.indexWhere((a) => a.id == article.id);
                _previewArticle = article;
              });
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RssArticleDetailScreen(article: article),
                ),
              );
            }
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

/// 未读徽标（0 时隐藏）
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 999 ? '999+' : '$count',
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimary),
      ),
    );
  }
}
