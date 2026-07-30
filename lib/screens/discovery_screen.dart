import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/discovery_item.dart';
import '../services/discovery_service.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'discovery_detail_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  final bool embedded;
  const DiscoveryScreen({super.key, this.embedded = false});

  @override
  State<DiscoveryScreen> createState() => DiscoveryScreenState();
}

class DiscoveryScreenState extends State<DiscoveryScreen> {
  final List<DiscoveryItem> _items = [];
  bool _isLoading = false;
  int _currentPage = 1;
  int _total = 0;
  final int _pageSize = 10;
  String _sort = 'order'; // 'order', 'time', or 'hot'
  int? _filterType; // null = all, 0=official, 1=recommended, 2=ad
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageJumpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData(refresh: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageJumpController.dispose();
    super.dispose();
  }

  int get _totalPages => (_total / _pageSize).ceil().clamp(1, 9999);

  Future<void> _loadData({bool refresh = false}) async {
    if (_isLoading) return;
    if (refresh) {
      _currentPage = 1;
      _items.clear();
    }

    setState(() => _isLoading = true);

    final result = await DiscoveryService.getDiscoveries(
      page: _currentPage,
      size: _pageSize,
      sort: _sort,
      type: _filterType,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result != null) {
        if (refresh) _items.clear();
        final newItems = List<DiscoveryItem>.from(result.items);
        if (_sort == 'order') {
          newItems.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        }
        _items.clear();
        _items.addAll(newItems);
        _total = result.total;
      }
    });
  }

  String get sortMode => _sort;

  void _toggleSort() {
    setState(() {
      if (_sort == 'order') {
        _sort = 'time';
      } else if (_sort == 'time') {
        _sort = 'hot';
      } else {
        _sort = 'order';
      }
    });
    _loadData(refresh: true);
  }

  void _setFilterType(int? type) {
    setState(() {
      _filterType = type;
    });
    _loadData(refresh: true);
  }

  void _goToPage(int page) {
    final target = page.clamp(1, _totalPages);
    if (target != _currentPage) {
      setState(() {
        _currentPage = target;
      });
      _loadData();
    }
  }

  void _jumpToPage() {
    final page = int.tryParse(_pageJumpController.text);
    if (page != null) {
      _goToPage(page);
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

  void toggleSort() => _toggleSort();

  void randomTap() => _onRandomTap();

  Future<void> _onRandomTap() async {
    final item = await DiscoveryService.getRandomDiscovery();
    if (!mounted) return;
    if (item != null) {
      _onItemTap(item);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No discovery items available')),
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

    if (widget.embedded) {
      return _buildBodyContent(context, loc, theme);
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
                    _sort == 'order'
                        ? Icons.sort
                        : _sort == 'hot'
                            ? Icons.local_fire_department
                            : Icons.access_time,
                  ),
                  tooltip: _sort == 'order'
                      ? loc.discoverySortOrder
                      : _sort == 'hot'
                          ? loc.discoverySortHot
                          : loc.discoverySortTime,
                  onPressed: _toggleSort,
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
                    _sort == 'order'
                        ? Icons.sort
                        : _sort == 'hot'
                            ? Icons.local_fire_department
                            : Icons.access_time,
                    size: 18,
                  ),
                  tooltip: _sort == 'order'
                      ? loc.discoverySortOrder
                      : _sort == 'hot'
                          ? loc.discoverySortHot
                          : loc.discoverySortTime,
                  onPressed: _toggleSort,
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
          // Type filter chips
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildFilterChip(loc, null, loc.discoveryFilterAll),
                _buildFilterChip(loc, 0, loc.discoveryTypeOfficial),
                _buildFilterChip(loc, 1, loc.discoveryTypeRecommended),
                _buildFilterChip(loc, 2, loc.discoveryTypeAd),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Total count + pagination
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildPaginationControls(theme),
            ),
          const SizedBox(height: 4),
          // List
          Expanded(
            child: _items.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
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
                        onRefresh: () => _loadData(refresh: true),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) {
                            return _buildItemCard(_items[i], theme);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent(BuildContext context, AppLocalizations loc, ThemeData theme) {
    return Column(
      children: [
        // Type filter chips
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildFilterChip(loc, null, loc.discoveryFilterAll),
              _buildFilterChip(loc, 0, loc.discoveryTypeOfficial),
              _buildFilterChip(loc, 1, loc.discoveryTypeRecommended),
              _buildFilterChip(loc, 2, loc.discoveryTypeAd),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Total count + pagination
        if (_total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildPaginationControls(theme),
          ),
        const SizedBox(height: 4),
        // List
        Expanded(
          child: _items.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
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
                      onRefresh: () => _loadData(refresh: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) {
                          return _buildItemCard(_items[i], theme);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(AppLocalizations loc, int? type, String label) {
    final isSelected = _filterType == type;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => _setFilterType(type),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildPaginationControls(ThemeData theme) {
    final loc = AppLocalizations.of(context);
    return Row(
      children: [
        // Page controls
        if (_totalPages > 1) ...[
          IconButton(
            icon: const Icon(Icons.first_page, size: 20),
            tooltip: loc.discoveryFirstPage,
            onPressed: _currentPage > 1 ? () => _goToPage(1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: loc.discoveryPrevPage,
            onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            alignment: Alignment.center,
            child: Text(
              '$_currentPage / $_totalPages',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: loc.discoveryNextPage,
            onPressed: _currentPage < _totalPages
                ? () => _goToPage(_currentPage + 1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 20),
            tooltip: loc.discoveryLastPage,
            onPressed: _currentPage < _totalPages
                ? () => _goToPage(_totalPages)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Page jump input
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onItemTap(item),
        onLongPress: () => _onItemLongPress(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon or type icon
              if (item.iconUrl != null && item.iconUrl!.isNotEmpty)
                ClipRRect(
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
                )
              else
                Container(
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
                ),
              const SizedBox(width: 12),
              // Content
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
                    // Tags
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
      ),
    );
  }
}
