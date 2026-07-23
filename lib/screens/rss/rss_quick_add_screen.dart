import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/feed_source.dart';
import '../../providers/rss_provider.dart';
import '../../services/rss_api_service.dart';
import '../../widgets/custom_title_bar.dart';

class RssQuickAddScreen extends StatefulWidget {
  const RssQuickAddScreen({super.key});

  @override
  State<RssQuickAddScreen> createState() => _RssQuickAddScreenState();
}

class _RssQuickAddScreenState extends State<RssQuickAddScreen> {
  final List<FeedSource> _feeds = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _loadingMore = false;
  int _currentPage = 1;
  int _total = 0;
  final int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  late Set<String> _existingUrls;

  // Folder state
  List<Map<String, dynamic>> _folders = [];
  int? _selectedFolderId;
  String? _selectedFolderName;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RssProvider>();
    _existingUrls = provider.feeds.map((f) => f.url).toSet();
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

  Future<void> _loadPage(int page) async {
    setState(() => _loading = page == 1);
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
      _selected.clear();
    });
    _loadPage(1);
  }

  void _addSingle(FeedSource feed) async {
    final provider = context.read<RssProvider>();
    final loc = AppLocalizations.of(context);
    final success = await provider.addFeedSource(feed);
    if (!mounted) return;
    if (success) {
      setState(() => _existingUrls.add(feed.url));
      // If viewing a folder, also add to local folder
      if (_selectedFolderId != null && feed.id != null) {
        provider.addSourceToFolder(_selectedFolderId!, feed.id!);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? loc.rssAddedToFolder.replaceAll('{name}', feed.title) : provider.error ?? 'Add failed')),
    );
  }

  void _batchAdd() async {
    if (_selected.isEmpty) return;
    final provider = context.read<RssProvider>();
    final loc = AppLocalizations.of(context);
    var added = 0;
    for (final index in _selected) {
      if (index >= _feeds.length) continue;
      final feed = _feeds[index];
      final success = await provider.addFeedSource(feed);
      if (success) {
        added++;
        _existingUrls.add(feed.url);
        if (_selectedFolderId != null && feed.id != null) {
          provider.addSourceToFolder(_selectedFolderId!, feed.id!);
        }
      }
    }
    setState(() => _selected.clear());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssBatchAdd.replaceAll('{count}', '$added'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = CustomTitleBar.isDesktop;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(_selectedFolderName ?? loc.rssRecommendedSources),
              actions: [
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _batchAdd,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(loc.rssBatchAdd.replaceAll('{count}', '${_selected.length}')),
                  ),
              ],
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: _selectedFolderName ?? loc.rssRecommendedSources,
              showBackButton: true,
              actions: [
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _batchAdd,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(loc.rssBatchAdd.replaceAll('{count}', '${_selected.length}')),
                  ),
              ],
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
                : _feeds.isEmpty
                    ? Center(child: Text(loc.rssNoSources))
                    : ListView.builder(
                        controller: _scrollController,
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
                          final isSelected = _selected.contains(index);
                          return CheckboxListTile(
                            value: alreadyAdded ? true : isSelected,
                            onChanged: alreadyAdded
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == true) {
                                        if (_selected.length >= 10) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(loc.rssMaxSelect)),
                                          );
                                          return;
                                        }
                                        _selected.add(index);
                                      } else {
                                        _selected.remove(index);
                                      }
                                    });
                                  },
                            title: Text(feed.title),
                            subtitle: Text(
                              feed.category.isNotEmpty ? '${feed.feedTypeLabel} · ${feed.category}' : feed.feedTypeLabel,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            secondary: alreadyAdded
                                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 22),
                                    onPressed: () => _addSingle(feed),
                                    tooltip: loc.confirm,
                                  ),
                            dense: true,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
