import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/feed_source.dart';
import '../../providers/rss_provider.dart';
import '../../services/rss_api_service.dart';
import '../../widgets/custom_title_bar.dart';

class RssQuickAddScreen extends StatefulWidget {
  final bool embedded;

  const RssQuickAddScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<RssQuickAddScreen> createState() => RssQuickAddScreenState();
}

class RssQuickAddScreenState extends State<RssQuickAddScreen> {
  final List<FeedSource> _feeds = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _currentPage = 1;
  int _total = 0;
  final int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  // Folder state
  List<Map<String, dynamic>> _folders = [];
  int? _selectedFolderId;
  String? _selectedFolderName;

  /// 已添加的订阅源 URL，实时取自 RssProvider，避免 initState 快照过时。
  Set<String> get _existingUrls =>
      context.read<RssProvider>().feeds.map((f) => f.url).toSet();

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _loadPage(1);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadFolders() async {
    final folders = await RssApiService.getFolders();
    if (mounted && folders != null) {
      setState(() => _folders = folders);
    }
  }

  Future<void> _loadPage(int page, {bool silent = false}) async {
    if (!silent) setState(() => _loading = page == 1);
    RssPageResult? result;
    if (_selectedFolderId != null) {
      result = await RssApiService.getFolderSources(_selectedFolderId!, page: page, size: _pageSize);
    } else {
      result = await RssApiService.getSources(page: page, size: _pageSize);
    }
    if (!mounted) return;
    if (result != null) {
      final data = result;
      setState(() {
        if (page == 1) _feeds.clear();
        _feeds.addAll(data.sources);
        _total = data.total;
        _currentPage = data.page;
        _loading = false;
        _loadingMore = false;
      });
    } else {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).unknownError)),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    if (_feeds.length >= _total) return;
    setState(() => _loadingMore = true);
    await _loadPage(_currentPage + 1);
  }

  void _selectFolder(int? folderId, String? folderName) {
    setState(() {
      _selectedFolderId = folderId;
      _selectedFolderName = folderName;
      _feeds.clear();
    });
    _loadPage(1);
  }

  void _addSingle(FeedSource feed) async {
    final provider = context.read<RssProvider>();
    final loc = AppLocalizations.of(context);
    final success = await provider.addFeedSource(feed);
    if (!mounted) return;
    if (success) {
      // _existingUrls 实时取自 provider.feeds，无需手动维护；
      // setState 触发重建以刷新“已添加”勾选状态。
      setState(() {});
      // If viewing a folder, also add to local folder
      if (_selectedFolderId != null && feed.id != null) {
        provider.addSourceToFolder(_selectedFolderId!, feed.id!);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? loc.rssAddedToFolder.replaceAll('{name}', feed.title) : (provider.error == null ? loc.unknownError : loc.translate(provider.error!)))),
    );
  }

  void _showFeedDetail(FeedSource feed) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feed.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(loc.rssFeedUrl, feed.url),
              if (feed.siteUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                _detailRow(loc.rssSite, feed.siteUrl),
              ],
              if (feed.category.isNotEmpty) ...[
                const SizedBox(height: 12),
                _detailRow(loc.rssFeedType, feed.category),
              ],
              const SizedBox(height: 12),
              _detailRow(loc.rssType, feed.feedTypeLabel),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.close),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey)),
        const SizedBox(height: 4),
        SelectableText(value, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBodyContent();
    }
    final isDesktop = CustomTitleBar.isDesktop;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(_selectedFolderName ?? loc.rssRecommendedSources),
            ),
      body: _buildBodyContent(),
    );
  }

  Widget _buildBodyContent() {
    final isDesktop = CustomTitleBar.isDesktop;
    final loc = AppLocalizations.of(context);

    return Column(
      children: [
        if (isDesktop)
          CustomTitleBar(
            title: _selectedFolderName ?? loc.rssRecommendedSources,
            showBackButton: true,
          ),
        // Folder chips
        if (_folders.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(loc.discoveryFilterAll),
                      selected: _selectedFolderId == null,
                      onSelected: (_) => _selectFolder(null, null),
                    ),
                  ),
                  ..._folders.map((f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('${f['name']} (${f['source_count'] ?? 0})'),
                      selected: _selectedFolderId == f['id'],
                      onSelected: (_) => _selectFolder(f['id'] as int, f['name'] as String),
                    ),
                  )),
                ],
              ),
            ),
          ),
        // Info bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedFolderId != null
                      ? loc.rssViewingFolder.replaceAll('{name}', _selectedFolderName ?? '')
                      : loc.rssFetchFromServer,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              if (_total > 0)
                Text(
                  loc.rssTotalCount.replaceAll('{count}', '$_total'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
            ],
          ),
        ),
        // Feed list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _loadPage(1, silent: true),
                  child: _feeds.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) => SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: constraints.maxHeight,
                              child: Center(child: Text(loc.rssNoSources)),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _feeds.length + (_feeds.length < _total ? 1 : 0),
                          itemBuilder: (context, index) {
                        if (index == _feeds.length) {
                          return _loadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : const SizedBox.shrink();
                        }
                        final feed = _feeds[index];
                        final alreadyAdded = _existingUrls.contains(feed.url);
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: ListTile(
                            title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              feed.category.isNotEmpty ? '${feed.feedTypeLabel} · ${feed.category}' : feed.feedTypeLabel,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.info_outline, size: 20),
                                  tooltip: loc.rssSourceInfo,
                                  onPressed: () => _showFeedDetail(feed),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                                if (alreadyAdded)
                                  Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20)
                                else
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 22),
                                    onPressed: () => _addSingle(feed),
                                    tooltip: loc.confirm,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  ),
                              ],
                            ),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      },
                    ),
                ),
        ),
      ],
    );
  }
}
