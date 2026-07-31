import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/discovery_item.dart';
import '../providers/discovery_provider.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'discovery_detail_screen.dart';
import '../services/discovery_service.dart';

class DiscoveryScreen extends StatefulWidget {
  final bool embedded;
  const DiscoveryScreen({super.key, this.embedded = false});

  @override
  State<DiscoveryScreen> createState() => DiscoveryScreenState();
}

class DiscoveryScreenState extends State<DiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageJumpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<DiscoveryProvider>();
    if (provider.items.isEmpty && !provider.isLoading) {
      provider.loadData(refresh: true);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageJumpController.dispose();
    super.dispose();
  }

  void _jumpToPage() {
    final page = int.tryParse(_pageJumpController.text);
    if (page != null) {
      context.read<DiscoveryProvider>().goToPage(page);
      _pageJumpController.clear();
    }
  }

  Future<void> _onItemTap(DiscoveryItem item) async {
    if (item.id != null) {
      DiscoveryService.recordClick(item.id!);
    }
    final uri = Uri.parse(item.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onItemLongPress(DiscoveryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoveryDetailScreen(item: item),
      ),
    );
  }

  void toggleSort() => context.read<DiscoveryProvider>().toggleSort();

  String get sortMode => context.read<DiscoveryProvider>().sortMode;

  void randomTap() => _onRandomTap();

  Future<void> _onRandomTap() async {
    final item = await DiscoveryService.getRandomDiscovery();
    if (!mounted) return;
    if (item != null) {
      _onItemTap(item);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).noDiscoveryItems)),
      );
    }
  }

  Color _typeColor(int type, ThemeData theme) {
    final scheme = theme.colorScheme;
    switch (type) {
      case 0:
        return scheme.primary;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.red;
      default:
        return scheme.outline;
    }
  }

  IconData _typeIcon(int type) {
    switch (type) {
      case 0:
        return Icons.verified;
      case 1:
        return Icons.star;
      case 2:
        return Icons.campaign;
      default:
        return Icons.help_outline;
    }
  }

  String _typeName(int type, AppLocalizations loc) {
    switch (type) {
      case 0:
        return loc.discoveryTypeOfficial;
      case 1:
        return loc.discoveryTypeRecommended;
      case 2:
        return loc.discoveryTypeAd;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = context.watch<DiscoveryProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;
    final total = provider.total;
    final sort = provider.sortMode;
    final filterType = provider.filterType;
    final currentPage = provider.currentPage;
    final totalPages = provider.totalPages;

    if (widget.embedded) {
      return _buildBodyContent(loc, theme, items, isLoading, total, filterType, currentPage, totalPages);
    }

    return Scaffold(
      appBar: CustomTitleBar.isDesktop
          ? null
          : AppBar(
              title: Text(loc.discover),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    sort == 'order'
                        ? Icons.sort
                        : sort == 'hot'
                            ? Icons.local_fire_department
                            : Icons.access_time,
                  ),
                  tooltip: sort == 'order'
                      ? loc.discoverySortOrder
                      : sort == 'hot'
                          ? loc.discoverySortHot
                          : loc.discoverySortTime,
                  onPressed: () => context.read<DiscoveryProvider>().toggleSort(),
                ),
                IconButton(
                  icon: const Icon(Icons.casino_outlined),
                  tooltip: loc.discoveryRandom,
                  onPressed: _onRandomTap,
                ),
              ],
            ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: loc.discover,
              showBackButton: true,
              actions: [
                IconButton(
                  icon: Icon(
                    sort == 'order'
                        ? Icons.sort
                        : sort == 'hot'
                            ? Icons.local_fire_department
                            : Icons.access_time,
                    size: 18,
                  ),
                  tooltip: sort == 'order'
                      ? loc.discoverySortOrder
                      : sort == 'hot'
                          ? loc.discoverySortHot
                          : loc.discoverySortTime,
                  onPressed: () => context.read<DiscoveryProvider>().toggleSort(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: const Icon(Icons.casino_outlined, size: 18),
                  tooltip: loc.discoveryRandom,
                  onPressed: _onRandomTap,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildFilterChip(loc, null, loc.discoveryFilterAll, filterType),
                _buildFilterChip(loc, 0, loc.discoveryTypeOfficial, filterType),
                _buildFilterChip(loc, 1, loc.discoveryTypeRecommended, filterType),
                _buildFilterChip(loc, 2, loc.discoveryTypeAd, filterType),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildPaginationControls(theme, currentPage, totalPages),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty && isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.explore,
                                size: 64, color: theme.colorScheme.outline),
                            const SizedBox(height: 16),
                            Text(loc.discoveryEmpty,
                                style: theme.textTheme.titleMedium),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => context.read<DiscoveryProvider>().loadData(refresh: true),
                        child: _buildItemList(items, theme),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(List<DiscoveryItem> items, ThemeData theme) {
    if (CustomTitleBar.isDesktop) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          // 每个条目最大宽度 420，窗口变窄时自动减少列数，
          // 保证单格不会缩到太窄（最小宽约 230，能完整放下图标+文字）。
          maxCrossAxisExtent: 420,
          // 固定条目高度：160 宣传图 + 上下 padding 24 + 图标/文字区约 136，
          // 高度不再随宽度缩放，防止下方内容被压缩变形或裁掉。
          mainAxisExtent: 275,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (ctx, i) => _buildItemCard(items[i], theme),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _buildItemCard(items[i], theme),
    );
  }

  Widget _buildBodyContent(AppLocalizations loc, ThemeData theme,
      List<DiscoveryItem> items, bool isLoading, int total, int? filterType, int currentPage, int totalPages) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildFilterChip(loc, null, loc.discoveryFilterAll, filterType),
              _buildFilterChip(loc, 0, loc.discoveryTypeOfficial, filterType),
              _buildFilterChip(loc, 1, loc.discoveryTypeRecommended, filterType),
              _buildFilterChip(loc, 2, loc.discoveryTypeAd, filterType),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildPaginationControls(theme, currentPage, totalPages),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: items.isEmpty && isLoading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.explore,
                              size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(loc.discoveryEmpty,
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => context.read<DiscoveryProvider>().loadData(refresh: true),
                      child: _buildItemList(items, theme),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(AppLocalizations loc, int? type, String label, int? currentFilterType) {
    final isSelected = currentFilterType == type;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => context.read<DiscoveryProvider>().setFilterType(type),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildPaginationControls(ThemeData theme, int currentPage, int totalPages) {
    final loc = AppLocalizations.of(context);
    return Row(
      children: [
        if (totalPages > 1) ...[
          IconButton(
            icon: const Icon(Icons.first_page, size: 20),
            tooltip: loc.discoveryFirstPage,
            onPressed: currentPage > 1 ? () => context.read<DiscoveryProvider>().goToPage(1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: loc.discoveryPrevPage,
            onPressed: currentPage > 1 ? () => context.read<DiscoveryProvider>().goToPage(currentPage - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            alignment: Alignment.center,
            child: Text(
              '$currentPage / $totalPages',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: loc.discoveryNextPage,
            onPressed: currentPage < totalPages
                ? () => context.read<DiscoveryProvider>().goToPage(currentPage + 1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 20),
            tooltip: loc.discoveryLastPage,
            onPressed: currentPage < totalPages
                ? () => context.read<DiscoveryProvider>().goToPage(totalPages)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          SizedBox(
            width: 56,
            height: 28,
            child: TextField(
              controller: _pageJumpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
                contentPadding: EdgeInsets.zero,
                isDense: true,
                hintText: loc.discoveryPage,
                hintStyle: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
              onSubmitted: (_) => _jumpToPage(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.arrow_forward, size: 18),
            tooltip: loc.discoveryJumpTo,
            onPressed: _jumpToPage,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ],
    );
  }

  Widget _buildItemCard(DiscoveryItem item, ThemeData theme) {
    final hasBanner = item.bannerUrl != null && item.bannerUrl!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: hasBanner ? Clip.antiAlias : Clip.none,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onItemTap(item),
        onLongPress: () => _onItemLongPress(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Banner image (top)
            if (hasBanner)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  item.bannerUrl!,
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            // Content area (icon + text)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  _buildItemIcon(item, theme),
                  const SizedBox(width: 12),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _typeColor(item.type, theme).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _typeName(item.type, AppLocalizations.of(context)),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _typeColor(item.type, theme),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (item.tagList.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: item.tagList.map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemIcon(DiscoveryItem item, ThemeData theme) {
    if (item.iconUrl != null && item.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          item.iconUrl!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _typeColor(item.type, theme).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _typeIcon(item.type),
              color: _typeColor(item.type, theme),
              size: 24,
            ),
          ),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _typeColor(item.type, theme).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _typeIcon(item.type),
        color: _typeColor(item.type, theme),
        size: 24,
      ),
    );
  }
}
