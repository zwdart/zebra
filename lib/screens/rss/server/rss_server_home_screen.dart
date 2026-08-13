import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/feed_source.dart';
import '../../../models/rss_article.dart';
import '../../../providers/rss_provider.dart';
import '../../../widgets/custom_title_bar.dart';
import '../rss_article_detail_screen.dart';
import 'rss_server_settings_screen.dart';

/// 服务器模式独立主页：服务器源侧栏 + 文章流 + 刷新(触发服务器抓取) + 未读徽标 + 设置入口。
/// 与离线模式页面完全独立，数据全部来自服务器 API。
class RssServerHomeScreen extends StatefulWidget {
  const RssServerHomeScreen({super.key});

  @override
  State<RssServerHomeScreen> createState() => _RssServerHomeScreenState();
}

class _RssServerHomeScreenState extends State<RssServerHomeScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RssProvider>().loadServerAll();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isWide => MediaQuery.sizeOf(context).width > 1000;

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<RssProvider>().loadMoreArticles();
    }
  }

  Future<void> _refresh() async {
    await context.read<RssProvider>().syncServerNow();
    if (!mounted) return;
    final error = context.read<RssProvider>().error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? AppLocalizations.of(context).rssSyncComplete)),
    );
  }

  void _selectSource(FeedSource? source) {
    // 选中数据源/全部时退出星标筛选,状态与加载统一由 Provider 管理
    context.read<RssProvider>().selectServerSource(source);
  }

  void _toggleStarredOnly() {
    // 星标筛选与数据源筛选互斥,状态与加载统一由 Provider 管理
    context.read<RssProvider>().toggleServerStarredOnly();
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RssServerSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;
    final provider = context.watch<RssProvider>();

    final actions = <Widget>[
      IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: () => _refresh(),
        tooltip: loc.rssSyncAll,
      ),
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        onPressed: _openSettings,
        tooltip: loc.rssServerSettings,
      ),
    ];

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(_title(loc)),
              actions: actions,
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(title: _title(loc), showBackButton: true, actions: actions),
          Expanded(
            child: _isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSideNav(provider, loc),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildArticleList(provider, loc)),
                    ],
                  )
                : Column(
                    children: [
                      _buildSourceChips(provider, loc),
                      Expanded(child: _buildArticleList(provider, loc)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _title(AppLocalizations loc) {
    final provider = context.read<RssProvider>();
    if (provider.serverStarredOnly) return '${loc.rssServerMode} · ${loc.rssFavorites}';
    if (provider.serverSelectedSource != null) return '${loc.rssServerMode} · ${provider.serverSelectedSource!.title}';
    return loc.rssServerMode;
  }

  // ==================== 源侧栏 ====================

  Widget _buildSideNav(RssProvider provider, AppLocalizations loc) {
    final theme = Theme.of(context);
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
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.article_outlined, size: 20),
                  title: Text(loc.discoveryFilterAll),
                  trailing: _UnreadBadge(count: provider.serverTotalUnread),
                  selected: provider.serverSelectedSource == null && !provider.serverStarredOnly,
                  onTap: () => _selectSource(null),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.star_border, size: 20),
                  title: Text(loc.rssFavorites),
                  selected: provider.serverStarredOnly,
                  onTap: _toggleStarredOnly,
                ),
                const Divider(height: 8),
                for (final source in provider.feeds)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.rss_feed, size: 20),
                    title: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: _UnreadBadge(count: provider.getServerUnreadForSource(source.id ?? -1)),
                    selected: provider.serverSelectedSource?.id == source.id,
                    onTap: () => _selectSource(source),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 窄屏数据源选择 ====================

  /// 窄屏(<1000dp)下横向展示数据源 chips,点击切换数据源/星标/全部。
  /// 与宽屏侧栏共用 _selectedSource/_starredOnly 状态与 _selectSource 逻辑。
  Widget _buildSourceChips(RssProvider provider, AppLocalizations loc) {
    final theme = Theme.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(loc.discoveryFilterAll),
              selected: provider.serverSelectedSource == null && !provider.serverStarredOnly,
              onSelected: (_) => _selectSource(null),
              selectedColor: theme.colorScheme.primaryContainer,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(loc.rssFavorites),
              avatar: Icon(
                Icons.star,
                size: 16,
                color: provider.serverStarredOnly ? theme.colorScheme.primary : null,
              ),
              selected: provider.serverStarredOnly,
              onSelected: (_) => _toggleStarredOnly(),
              selectedColor: theme.colorScheme.primaryContainer,
            ),
          ),
          for (final source in provider.feeds)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: provider.serverSelectedSource?.id == source.id,
                onSelected: (_) => _selectSource(source),
                selectedColor: theme.colorScheme.primaryContainer,
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 文章流 ====================

  Widget _buildArticleList(RssProvider provider, AppLocalizations loc) {
    if (provider.isLoading && provider.articles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.articles.isEmpty) {
      return _buildEmptyState(provider, loc);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
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
          return _buildArticleCard(provider, provider.articles[index], loc);
        },
      ),
    );
  }

  Widget _buildEmptyState(RssProvider provider, AppLocalizations loc) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(loc.rssNoArticles, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            provider.error != null && provider.error!.isNotEmpty
                ? loc.rssSyncFailed
                : loc.rssNoArticlesHint,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await _refresh();
              if (!mounted) return;
            },
            icon: const Icon(Icons.refresh),
            label: Text(loc.rssSyncNow),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleCard(RssProvider provider, RssArticle article, AppLocalizations loc) {
    final theme = Theme.of(context);
    final sourceTitle = provider.feeds
        .where((f) => f.id == article.feedSourceId)
        .map((f) => f.title)
        .firstOrNull;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            article.title.isNotEmpty ? article.title.characters.first : '?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
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
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              if (sourceTitle != null && sourceTitle.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(sourceTitle, style: theme.textTheme.labelSmall),
                ),
                const SizedBox(width: 8),
              ],
              Text(article.displayTime, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            article.isStarred ? Icons.star : Icons.star_border,
            color: article.isStarred ? Colors.amber : null,
          ),
          onPressed: () =>
              provider.syncServerState(article.id!, starred: !article.isStarred),
        ),
        onTap: () {
          if (!article.isRead) {
            provider.syncServerState(article.id!, read: true);
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RssArticleDetailScreen(article: article),
            ),
          );
        },
      ),
    );
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
