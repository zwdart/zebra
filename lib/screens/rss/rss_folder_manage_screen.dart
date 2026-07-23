import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/feed_source.dart';
import '../../providers/rss_provider.dart';
import '../../widgets/custom_title_bar.dart';
import 'rss_article_list_screen.dart';

class RssFolderManageScreen extends StatefulWidget {
  const RssFolderManageScreen({super.key});

  @override
  State<RssFolderManageScreen> createState() => _RssFolderManageScreenState();
}

class _RssFolderManageScreenState extends State<RssFolderManageScreen> {
  @override
  Widget build(BuildContext context) {
    final isDesktop = CustomTitleBar.isDesktop;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(loc.rssFolderManagement),
              actions: [
                IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () => _syncAllFolders(context),
                  tooltip: loc.rssSyncAll,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showCreateFolderDialog(context),
                  tooltip: loc.rssCreateFolder,
                ),
              ],
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: loc.rssFolderManagement,
              showBackButton: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.sync, size: 18),
                  onPressed: () => _syncAllFolders(context),
                  tooltip: loc.rssSyncAll,
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _showCreateFolderDialog(context),
                  tooltip: loc.rssCreateFolder,
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
        final folders = provider.getAllFolders();
        if (folders.isEmpty) {
          return _buildEmptyState(context);
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            return _buildFolderTile(context, folder);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(loc.rssNoFolders, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(loc.rssNoFoldersHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showCreateFolderDialog(context),
            icon: const Icon(Icons.add),
            label: Text(loc.rssCreateFolder),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(BuildContext context, Map<String, dynamic> folder) {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    final sourceCount = provider.getFolderSources(folder['id'] as int).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.folder, size: 20),
        ),
        title: Text(folder['name'] as String),
        subtitle: Text(
          '${folder['description'] ?? ''}${sourceCount > 0 ? ' · ${loc.rssSourcesCountValue(sourceCount)}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleFolderMenuAction(context, value, folder),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'open', child: Text('View')),
            PopupMenuItem(value: 'edit', child: Text(loc.rssEditSource)),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text(loc.delete, style: const TextStyle(color: Colors.red))),
          ],
        ),
        onTap: () => _openFolder(context, folder),
      ),
    );
  }

  void _handleFolderMenuAction(BuildContext context, String value, Map<String, dynamic> folder) {
    switch (value) {
      case 'open':
        _openFolder(context, folder);
        break;
      case 'edit':
        _showEditFolderDialog(context, folder);
        break;
      case 'delete':
        _confirmDeleteFolder(context, folder);
        break;
    }
  }

  void _showCreateFolderDialog(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssCreateFolder),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: loc.rssFolderName),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: InputDecoration(labelText: loc.rssFolderDescOptional),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              context.read<RssProvider>().createFolder(name, descController.text.trim());
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  void _showEditFolderDialog(BuildContext context, Map<String, dynamic> folder) {
    final loc = AppLocalizations.of(context);
    final nameController = TextEditingController(text: folder['name'] as String);
    final descController = TextEditingController(text: folder['description'] as String? ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssEditFolder),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: loc.name),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: InputDecoration(labelText: loc.rssFolderDesc),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              context.read<RssProvider>().updateFolder(
                folder['id'] as int, name, descController.text.trim(),
              );
            },
            child: Text(loc.save),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(BuildContext context, Map<String, dynamic> folder) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssDeleteFolder),
        content: Text(loc.rssDeleteFolderConfirmValue(folder['name'] as String)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<RssProvider>().deleteFolder(folder['id'] as int);
            },
            child: Text(loc.delete),
          ),
        ],
      ),
    );
  }

  void _openFolder(BuildContext context, Map<String, dynamic> folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(folder: folder),
      ),
    );
  }

  Future<void> _syncAllFolders(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.rssSyncingAll), duration: const Duration(seconds: 1)),
    );
    await provider.syncAll();
    if (context.mounted) {
      final error = provider.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? loc.rssSyncComplete)),
      );
    }
  }
}

/// Folder detail screen showing RSS sources within the folder.
/// Supports: view sources, add source, batch delete, edit source, remove from folder.
class FolderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> folder;
  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<FeedSource> _sources = [];
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  void _loadSources() {
    final provider = context.read<RssProvider>();
    setState(() {
      _sources = provider.getFolderSources(widget.folder['id'] as int);
    });
  }

  int get _folderId => widget.folder['id'] as int;

  @override
  Widget build(BuildContext context) {
    final isDesktop = CustomTitleBar.isDesktop;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: _selectMode
                  ? Text(loc.rssSelectedCountValue(_selectedIds.length))
                  : Text(widget.folder['name'] as String),
              leading: _selectMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _selectMode = false;
                        _selectedIds.clear();
                      }),
                    )
                  : null,
              actions: [
                if (_selectMode) ...[
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    onPressed: _selectAll,
                    tooltip: loc.rssSelectAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _selectedIds.isEmpty ? null : _batchRemoveFromFolder,
                    tooltip: loc.rssRemoveFromFolder,
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: _syncAllSources,
                    tooltip: loc.rssSyncAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddSourceDialog(context),
                    tooltip: loc.rssAddSource,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _handleMenuAction(context, value),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'add_local', child: Text(loc.rssAddToLocal)),
                      PopupMenuItem(value: 'add_url', child: Text(loc.rssAddByUrl)),
                      PopupMenuItem(value: 'batch_delete', child: Text(loc.rssBatchDelete)),
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'refresh', child: Text(loc.rssRefreshList)),
                    ],
                  ),
                ],
              ],
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: _selectMode
                  ? loc.rssSelectedCountValue(_selectedIds.length)
                  : widget.folder['name'] as String,
              showBackButton: true,
              actions: [
                if (_selectMode) ...[
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    onPressed: _selectAll,
                    tooltip: loc.rssSelectAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _selectedIds.isEmpty ? null : _batchRemoveFromFolder,
                    tooltip: loc.rssRemoveFromFolder,
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.sync, size: 18),
                    onPressed: _syncAllSources,
                    tooltip: loc.rssSyncAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => _showAddLocalSourcesSheet(context),
                    tooltip: loc.rssAddFromLocal,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _handleMenuAction(context, value),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'add_local', child: Text(loc.rssAddToLocal)),
                      PopupMenuItem(value: 'add_url', child: Text(loc.rssAddByUrl)),
                      PopupMenuItem(value: 'batch_delete', child: Text(loc.rssBatchDelete)),
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'refresh', child: Text(loc.rssRefreshList)),
                    ],
                  ),
                ],
              ],
            ),
          Expanded(child: _buildSourceList()),
        ],
      ),
    );
  }

  Widget _buildSourceList() {
    if (_sources.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _sources.length,
      itemBuilder: (context, index) {
        final source = _sources[index];
        final isSelected = _selectedIds.contains(source.id);

        return _selectMode
            ? _buildSelectableSourceTile(source, isSelected)
            : _buildSourceTile(source);
      },
    );
  }

  Widget _buildEmptyState() {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rss_feed_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(loc.rssFolderEmpty, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(loc.rssFolderEmptyHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddLocalSourcesSheet(context),
            icon: const Icon(Icons.add),
            label: Text(loc.rssAddToLocal),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTile(FeedSource source) {
    final loc = AppLocalizations.of(context);
    final unread = context.read<RssProvider>().getUnreadCountForFeed(source.id!);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: source.iconUrl.isNotEmpty
              ? ClipOval(child: Image.network(source.iconUrl, width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.rss_feed)))
              : const Icon(Icons.rss_feed),
        ),
        title: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(source.feedTypeLabel, style: Theme.of(context).textTheme.labelSmall),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$unread ${loc.rssUnread}', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 11)),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleSourceMenuAction(context, value, source),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'sync', child: Text(loc.rssSyncSource)),
            PopupMenuItem(value: 'edit', child: Text(loc.rssEditSource)),
            PopupMenuItem(value: 'view', child: Text(loc.rssViewArticle)),
            PopupMenuItem(value: 'remove', child: Text(loc.rssRemoveFromFolder)),
          ],
        ),
        onTap: () {
          context.read<RssProvider>().loadArticles(source.id!, refresh: true);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RssArticleListScreen(feedSource: source),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectableSourceTile(FeedSource source, bool isSelected) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: ListTile(
        leading: CircleAvatar(
          child: source.iconUrl.isNotEmpty
              ? ClipOval(child: Image.network(source.iconUrl, width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.rss_feed)))
              : const Icon(Icons.rss_feed),
        ),
        title: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(source.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selectedIds.add(source.id!);
              } else {
                _selectedIds.remove(source.id!);
              }
            });
          },
        ),
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(source.id!);
            } else {
              _selectedIds.add(source.id!);
            }
          });
        },
      ),
    );
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _sources.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_sources.map((s) => s.id!));
      }
    });
  }

  void _handleMenuAction(BuildContext context, String value) {
    switch (value) {
      case 'add_local':
        _showAddLocalSourcesSheet(context);
        break;
      case 'add_url':
        _showAddSourceDialog(context);
        break;
      case 'batch_delete':
        setState(() {
          _selectMode = true;
          _selectedIds.clear();
        });
        break;
      case 'refresh':
        _loadSources();
        break;
    }
  }

  void _handleSourceMenuAction(BuildContext context, String value, FeedSource source) {
    switch (value) {
      case 'sync':
        _syncSource(context, source);
        break;
      case 'edit':
        _showEditSourceDialog(context, source);
        break;
      case 'view':
        context.read<RssProvider>().loadArticles(source.id!, refresh: true);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RssArticleListScreen(feedSource: source),
          ),
        );
        break;
      case 'remove':
        _confirmRemoveFromFolder(context, source);
        break;
    }
  }

  Future<void> _syncAllSources() async {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.rssSyncingFolder), duration: const Duration(seconds: 1)),
    );

    var synced = 0;
    for (final source in _sources) {
      await provider.syncFeedSourceById(source.id!);
      synced++;
    }

    _loadSources();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssSyncedCountValue(synced))),
      );
    }
  }

  Future<void> _syncSource(BuildContext context, FeedSource source) async {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.rssSyncingSourceValue(source.title)), duration: const Duration(seconds: 1)),
    );
    await provider.syncFeedSourceById(source.id!);
    _loadSources();
    if (mounted) {
      final error = provider.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? loc.rssSyncComplete)),
      );
    }
  }

  void _showAddSourceDialog(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final urlController = TextEditingController();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssAddToFolderTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: loc.rssFeedUrl,
                hintText: 'https://example.com/feed.xml',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: loc.rssFeedTitle,
                hintText: loc.rssFeedTitleHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(context);
              await _addSourceFromUrl(url, titleController.text.trim());
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _addSourceFromUrl(String url, String title) async {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    final source = FeedSource(
      title: title.isNotEmpty ? title : url,
      url: url,
    );
    final success = await provider.addFeedSource(source);
    if (success && mounted) {
      // Get the saved source to obtain the correct id.
      final savedSource = provider.getFeedSourceByUrl(url);
      if (savedSource != null) {
        provider.addSourceToFolder(_folderId, savedSource.id!);
      }
      _loadSources();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feed added to folder')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error ?? 'Add failed')),
      );
    }
  }

  void _showEditSourceDialog(BuildContext context, FeedSource source) {
    final loc = AppLocalizations.of(context);
    final titleController = TextEditingController(text: source.title);
    final urlController = TextEditingController(text: source.url);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssEditSource),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(labelText: loc.rssFeedTitle),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(context);
              context.read<RssProvider>().updateFeedSource(
                source.copyWith(title: title, url: urlController.text.trim()),
              );
              _loadSources();
            },
            child: Text(loc.save),
          ),
        ],
      ),
    );
  }

  void _showAddLocalSourcesSheet(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    final localFeeds = provider.feeds;
    final currentFolderUrls = _sources.map((s) => s.url).toSet();

    // Filter out sources already in this folder.
    final availableFeeds = localFeeds.where((f) => !currentFolderUrls.contains(f.url)).toList();

    if (availableFeeds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssNoAddableSources)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return _LocalSourcesSheet(
            folderId: _folderId,
            availableFeeds: availableFeeds,
            scrollController: scrollController,
            onSourcesAdded: () {
              _loadSources();
            },
          );
        },
      ),
    );
  }

  void _confirmRemoveFromFolder(BuildContext context, FeedSource source) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssRemoveFromFolder),
        content: Text(loc.rssRemoveConfirmValue(source.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<RssProvider>().removeSourceFromFolder(_folderId, source.id!);
              _loadSources();
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  void _batchRemoveFromFolder() {
    if (_selectedIds.isEmpty) return;

    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssBatchRemove),
        content: Text(loc.rssBatchRemoveConfirmValue(_selectedIds.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              final provider = context.read<RssProvider>();
              for (final id in _selectedIds) {
                provider.removeSourceFromFolder(_folderId, id);
              }
              setState(() {
                _selectMode = false;
                _selectedIds.clear();
              });
              _loadSources();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.rssRemoved)),
              );
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

}

/// Sheet for adding local RSS sources to the folder.
class _LocalSourcesSheet extends StatefulWidget {
  final int folderId;
  final List<FeedSource> availableFeeds;
  final ScrollController scrollController;
  final VoidCallback onSourcesAdded;

  const _LocalSourcesSheet({
    required this.folderId,
    required this.availableFeeds,
    required this.scrollController,
    required this.onSourcesAdded,
  });

  @override
  State<_LocalSourcesSheet> createState() => _LocalSourcesSheetState();
}

class _LocalSourcesSheetState extends State<_LocalSourcesSheet> {
  final Set<int> _selectedIds = {};
  String _searchQuery = '';

  List<FeedSource> get _filteredFeeds {
    if (_searchQuery.isEmpty) return widget.availableFeeds;
    final query = _searchQuery.toLowerCase();
    return widget.availableFeeds.where((f) =>
      f.title.toLowerCase().contains(query) ||
      f.url.toLowerCase().contains(query)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      loc.rssAddFromLocal,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_selectedIds.isNotEmpty)
                    TextButton.icon(
                      onPressed: _batchAddToFolder,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text(loc.rssBatchAddValue(_selectedIds.length)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: loc.rssSearchSources,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredFeeds.isEmpty
              ? Center(child: Text(loc.rssNoAddableSources))
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: _filteredFeeds.length,
                  itemBuilder: (context, index) {
                    final feed = _filteredFeeds[index];
                    final isSelected = _selectedIds.contains(feed.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIds.add(feed.id!);
                          } else {
                            _selectedIds.remove(feed.id);
                          }
                        });
                      },
                      title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        feed.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      secondary: CircleAvatar(
                        child: feed.iconUrl.isNotEmpty
                            ? ClipOval(child: Image.network(feed.iconUrl, width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.rss_feed)))
                            : const Icon(Icons.rss_feed),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _batchAddToFolder() {
    if (_selectedIds.isEmpty) return;

    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    var added = 0;
    for (final id in _selectedIds) {
      provider.addSourceToFolder(widget.folderId, id);
      added++;
    }

    widget.onSourcesAdded();
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.rssAddedCountValue(added))),
    );
  }
}
