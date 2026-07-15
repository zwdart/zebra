import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/discovery_item.dart';
import '../services/discovery_service.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final List<DiscoveryItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _total = 0;
  String _sort = 'time'; // 'time' or 'hot'
  int? _filterType; // null = all, 0=official, 1=recommended, 2=ad

  @override
  void initState() {
    super.initState();
    _loadData(refresh: true);
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (_isLoading) return;
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore && !refresh) return;

    setState(() => _isLoading = true);

    final result = await DiscoveryService.getDiscoveries(
      page: _currentPage,
      size: 10,
      sort: _sort,
      type: _filterType,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result != null) {
        if (refresh) _items.clear();
        _items.addAll(result.items);
        _total = result.total;
        _hasMore = result.hasMore;
        _currentPage++;
      }
    });
  }

  void _toggleSort() {
    setState(() {
      _sort = _sort == 'time' ? 'hot' : 'time';
    });
    _loadData(refresh: true);
  }

  void _setFilterType(int? type) {
    setState(() {
      _filterType = type;
    });
    _loadData(refresh: true);
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
                  icon: Icon(_sort == 'hot' ? Icons.local_fire_department : Icons.access_time),
                  tooltip: _sort == 'hot' ? loc.discoverySortHot : loc.discoverySortTime,
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
                    _sort == 'hot' ? Icons.local_fire_department : Icons.access_time,
                    size: 18,
                  ),
                  tooltip: _sort == 'hot' ? loc.discoverySortHot : loc.discoverySortTime,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          // Total count
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${loc.discoveryTotal}: $_total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
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
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _items.length) {
                              // Load more trigger
                              _loadData();
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final item = _items[i];
                            return _buildItemCard(item, theme);
                          },
                        ),
                      ),
          ),
        ],
      ),
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

  Widget _buildItemCard(DiscoveryItem item, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onItemTap(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Type icon
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
                  size: 22,
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.touch_app,
                            size: 12, color: theme.colorScheme.outline),
                        const SizedBox(width: 2),
                        Text(
                          '${item.clicks}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.open_in_new,
                            size: 12, color: theme.colorScheme.outline),
                      ],
                    ),
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
