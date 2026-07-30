import 'package:flutter/material.dart';
import '../../widgets/custom_title_bar.dart';
import '../../l10n/app_localizations.dart';
import 'rss_quick_add_screen.dart';
import 'rss_source_manage_screen.dart';
import '../discovery_screen.dart';
import '../blog_screen.dart';

class RssExploreScreen extends StatefulWidget {
  final int initialTab;

  const RssExploreScreen({super.key, this.initialTab = 0});

  @override
  State<RssExploreScreen> createState() => _RssExploreScreenState();
}

class _RssExploreScreenState extends State<RssExploreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final GlobalKey<DiscoveryScreenState> _discoveryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Widget> _buildActions(AppLocalizations loc) {
    if (_tabController.index == 0) {
      // 推荐 tab
      return [
        IconButton(
          icon: const Icon(Icons.rss_feed),
          tooltip: loc.rssFeedManagement,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RssSourceManageScreen()),
          ),
        ),
      ];
    } else if (_tabController.index == 1) {
      // 发现 tab
      final currentSort = _discoveryKey.currentState?.sortMode ?? 'order';
      final sortIcon = currentSort == 'order'
          ? Icons.sort
          : currentSort == 'hot'
              ? Icons.local_fire_department
              : Icons.access_time;
      final sortTooltip = currentSort == 'order'
          ? loc.discoverySortOrder
          : currentSort == 'hot'
              ? loc.discoverySortHot
              : loc.discoverySortTime;
      return [
        IconButton(
          icon: Icon(sortIcon),
          tooltip: sortTooltip,
          onPressed: () => _discoveryKey.currentState?.toggleSort(),
        ),
        IconButton(
          icon: const Icon(Icons.casino_outlined),
          tooltip: loc.discoveryRandom,
          onPressed: () => _discoveryKey.currentState?.randomTap(),
        ),
      ];
    } else {
      // 博客 tab — no toolbar actions needed
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(loc.rssExplore),
              actions: _buildActions(loc),
              bottom: TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: loc.rssRecommended),
                  Tab(text: loc.discover),
                  Tab(text: loc.blog),
                ],
              ),
            ),
      body: Column(
        children: [
          if (isDesktop)
            CustomTitleBar(
              title: loc.rssExplore,
              showBackButton: true,
              actions: _buildActions(loc),
            ),
          if (isDesktop)
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: loc.rssRecommended),
                  Tab(text: loc.discover),
                  Tab(text: loc.blog),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                RssQuickAddScreen(
                  embedded: true,
                ),
                DiscoveryScreen(
                  key: _discoveryKey,
                  embedded: true,
                ),
                const BlogScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
