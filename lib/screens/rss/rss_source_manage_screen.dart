import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/rss_provider.dart';
import '../../models/feed_source.dart';
import '../../utils/zebra_paths.dart';
import '../../widgets/custom_title_bar.dart';
import 'rss_article_list_screen.dart';
import 'rss_explore_screen.dart';
import 'rss_folder_manage_screen.dart';
import '../../l10n/app_localizations.dart';

class RssSourceManageScreen extends StatelessWidget {
  const RssSourceManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(loc.rssSubscription),
              actions: [
                IconButton(
                  icon: const Icon(Icons.folder_special),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RssFolderManageScreen()),
                  ),
                  tooltip: loc.rssFolderManagement,
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(context, value),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'quick_add', child: Text(loc.rssRecommended)),
                    PopupMenuItem(value: 'manual_add', child: Text(loc.rssManualAdd)),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'import_csv', child: Text(loc.rssImportCsv)),
                    PopupMenuItem(value: 'import_opml', child: Text(loc.rssImportOpml)),
                    PopupMenuItem(value: 'export_csv', child: Text(loc.rssExportCsv)),
                    PopupMenuItem(value: 'export_opml', child: Text(loc.rssExportOpml)),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: loc.rssSubscription,
              showBackButton: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.folder_special),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RssFolderManageScreen()),
                  ),
                  tooltip: loc.rssFolderManagement,
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(context, value),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'quick_add', child: Text(loc.rssRecommended)),
                    PopupMenuItem(value: 'manual_add', child: Text(loc.rssManualAdd)),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'import_csv', child: Text(loc.rssImportCsv)),
                    PopupMenuItem(value: 'import_opml', child: Text(loc.rssImportOpml)),
                    PopupMenuItem(value: 'export_csv', child: Text(loc.rssExportCsv)),
                    PopupMenuItem(value: 'export_opml', child: Text(loc.rssExportOpml)),
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
        if (provider.feeds.isEmpty) {
          return _buildEmptyState(context);
        }

        return Column(
          children: [
            // Quick add banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(AppLocalizations.of(context).rssOneClickAdd, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  TextButton(
                    onPressed: () => _showQuickAddDialog(context),
                    child: Text(AppLocalizations.of(context).view),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: provider.feeds.length,
                itemBuilder: (context, index) {
                  final feed = provider.feeds[index];
                  return _buildSourceTile(context, feed);
                },
              ),
            ),
          ],
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
          Icon(Icons.rss_feed, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(loc.rssNoSources, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(loc.rssSourceEmptyHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showQuickAddDialog(context),
            icon: const Icon(Icons.auto_awesome),
            label: Text(loc.rssRecommended),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showAddDialog(context),
            icon: const Icon(Icons.add),
            label: Text(loc.rssManualAdd),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTile(BuildContext context, FeedSource feed) {
    final loc = AppLocalizations.of(context);
    final unread = context.read<RssProvider>().getUnreadCountForFeed(feed.id!);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: feed.iconUrl.isNotEmpty
              ? ClipOval(child: Image.network(feed.iconUrl, width: 40, height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.rss_feed)))
              : const Icon(Icons.rss_feed),
        ),
        title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(feed.feedTypeLabel, style: Theme.of(context).textTheme.labelSmall),
            ),
            const SizedBox(width: 8),
            if (unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$unread ${loc.rssUnread}', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 11)),
              ),
            if (feed.source == 'server') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Favorites', style: Theme.of(context).textTheme.labelSmall),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // IconButton(
            //   icon: const Icon(Icons.info_outline, size: 20),
            //   tooltip: loc.rssSourceInfo,
            //   onPressed: () => _showFeedInfo(context, feed),
            //   padding: EdgeInsets.zero,
            //   constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            // ),
            PopupMenuButton<String>(
          onSelected: (value) => _handleSourceMenuAction(context, value, feed),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'sync', child: Text(loc.rssSyncSource)),
            PopupMenuItem(value: 'view', child: Text(loc.rssViewArticle)),
            PopupMenuItem(value: 'info', child: Text(loc.rssSourceInfo)),
            PopupMenuItem(value: 'edit', child: Text(loc.rssEditSource)),
            PopupMenuItem(value: 'folder', child: Text(loc.rssAddToFolder)),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text(loc.delete, style: const TextStyle(color: Colors.red))),
          ],
        ),
          ],
        ),
        onTap: () {
          context.read<RssProvider>().loadArticles(feed.id!, refresh: true);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RssArticleListScreen(feedSource: feed),
            ),
          );
        },
      ),
    );
  }

  void _handleSourceMenuAction(BuildContext context, String value, FeedSource feed) {
    switch (value) {
      case 'sync':
        _syncFeed(context, feed);
        break;
      case 'view':
        context.read<RssProvider>().loadArticles(feed.id!, refresh: true);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RssArticleListScreen(feedSource: feed)),
        );
        break;
      case 'info':
        _showFeedInfo(context, feed);
        break;
      case 'edit':
        _showEditDialog(context, feed);
        break;
      case 'folder':
        _showSingleAddToFolderDialog(context, feed);
        break;
      case 'delete':
        _confirmDelete(context, feed);
        break;
    }
  }

  void _showSingleAddToFolderDialog(BuildContext context, FeedSource feed) {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    final folders = provider.getAllFolders();

    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssNoFoldersAvailable)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(loc.rssAddToFolderTitle.replaceAll('{name}', feed.title), style: Theme.of(context).textTheme.titleMedium),
            ),
            ...folders.map((folder) => ListTile(
              leading: const Icon(Icons.folder),
              title: Text(folder['name'] as String),
              subtitle: Text(loc.rssSourcesCount.replaceAll('{count}', '${folder['source_count'] ?? 0}')),
              onTap: () {
                provider.addSourceToFolder(folder['id'] as int, feed.id!);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.rssAddedToFolder.replaceAll('{name}', folder['name'] as String))),
                );
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showQuickAddDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RssExploreScreen()),
    );
  }

  void _handleMenuAction(BuildContext context, String value) {
    switch (value) {
      case 'quick_add':
        _showQuickAddDialog(context);
        break;
      case 'manual_add':
        _showAddDialog(context);
        break;
      case 'import_csv':
        _importCsv(context);
        break;
      case 'import_opml':
        _importOpml(context);
        break;
      case 'export_csv':
        _exportCsv(context);
        break;
      case 'export_opml':
        _exportOpml(context);
        break;
    }
  }

  Future<void> _importCsv(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();
    final provider = context.read<RssProvider>();
    final sources = provider.importFromCsv(content);

    if (context.mounted) {
      final loc = AppLocalizations.of(context);
      final count = provider.importSources(sources);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssImportComplete.replaceAll('{count}', '$count'))),
      );
    }
  }

  Future<void> _importOpml(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['opml', 'xml'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();
    final provider = context.read<RssProvider>();
    final sources = provider.importFromOpml(content);

    if (context.mounted) {
      final loc = AppLocalizations.of(context);
      final count = provider.importSources(sources);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssImportComplete.replaceAll('{count}', '$count'))),
      );
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final provider = context.read<RssProvider>();
    final csv = provider.exportToCsv();
    final ts = _timestamp();
    await _saveAndShowPath(context, csv, 'rss_subscriptions_$ts.csv');
  }

  Future<void> _exportOpml(BuildContext context) async {
    final provider = context.read<RssProvider>();
    final opml = provider.exportToOpml();
    final ts = _timestamp();
    await _saveAndShowPath(context, opml, 'rss_subscriptions_$ts.opml');
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _saveAndShowPath(BuildContext context, String content, String filename) async {
    final path = await ZebraPaths.filePath('rss', filename);
    final file = File(path);
    await file.writeAsString(content);

    if (context.mounted) {
      final loc = AppLocalizations.of(context);
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(loc.rssExportSuccess),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.rssFileSavedTo),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  file.path,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.rssClose),
            ),
            FilledButton(
              onPressed: () {
                Share.shareXFiles([XFile(file.path)], subject: filename);
                Navigator.pop(context);
              },
              child: Text(loc.share),
            ),
          ],
        ),
      );
    }
  }

  void _showAddDialog(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final urlController = TextEditingController();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssAddSource),
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
                hintText: 'Leave empty to auto-fetch',
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
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(context);
              context.read<RssProvider>().addFeedSourceFromUrl(
                    url,
                    title: titleController.text.trim().isNotEmpty ? titleController.text.trim() : null,
                  );
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, FeedSource feed) {
    final loc = AppLocalizations.of(context);
    final titleController = TextEditingController(text: feed.title);
    final urlController = TextEditingController(text: feed.url);

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
              decoration: InputDecoration(labelText: loc.rssFeedUrl),
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
                    feed.copyWith(title: title, url: urlController.text.trim()),
                  );
            },
            child: Text(loc.save),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, FeedSource feed) {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();
    final folders = provider.getSourceFolderReferences(feed.id!);

    final content = StringBuffer(loc.rssDeleteSourceConfirm.replaceAll('{title}', feed.title));
    if (folders.isNotEmpty) {
      for (final f in folders) {
        content.write('\n· ${f['name']}');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssDeleteSource),
        content: Text(content.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteFeedSource(feed.id!);
            },
            child: Text(loc.delete),
          ),
        ],
      ),
    );
  }

  void _syncFeed(BuildContext context, FeedSource feed) async {
    final loc = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.rssSyncingSource.replaceAll('{name}', feed.title)), duration: const Duration(seconds: 1)),
    );
    await context.read<RssProvider>().syncFeedSourceById(feed.id!);
    if (!context.mounted) return;
    final error = context.read<RssProvider>().error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? loc.rssSyncComplete)),
    );
  }

  void _showFeedInfo(BuildContext context, FeedSource feed) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feed.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(loc.rssType, feed.feedTypeLabel),
            _infoRow('URL', feed.url),
            if (feed.siteUrl.isNotEmpty) _infoRow(loc.rssSite, feed.siteUrl),
            if (feed.lastSyncedAt != null) _infoRow(loc.rssLastSync, feed.lastSyncedAt!),
            if (feed.lastSyncError != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.rssSyncError,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      feed.lastSyncError!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.rssClose),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
