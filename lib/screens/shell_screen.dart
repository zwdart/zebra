import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'rss/rss_feed_list_screen.dart';
import 'home_screen.dart';
import 'diary_screen.dart';
import 'settings_screen.dart';
import '../features/qr_tool/screens/qr_tool_screen.dart';
import 'update_dialog.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectionProvider>().loadConnections();
      _silentCheckUpdate(context);
    });
  }

  void _silentCheckUpdate(BuildContext context) async {
    final provider = context.read<UpdateProvider>();
    await provider.silentCheck();
    if (provider.state == UpdateState.hasUpdate && context.mounted) {
      final isSkipValid = await UpdateService.isSkipUpdateValid();
      if (!isSkipValid) {
        showDialog(
          context: context,
          barrierDismissible: !provider.forceUpdate,
          builder: (_) => const UpdateDialog(showSkip: true),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;

    final tabs = [
      const RssFeedListScreen(),
      const HomeScreen(),
      const DiaryScreen(),
      const QrToolScreen(),
      const SettingsScreen(),
    ];

    final navItems = [
      NavigationDestination(
        icon: const Icon(Icons.rss_feed_outlined),
        selectedIcon: const Icon(Icons.rss_feed),
        label: 'RSS',
      ),
      NavigationDestination(
        icon: const Icon(Icons.computer_outlined),
        selectedIcon: const Icon(Icons.computer),
        label: 'SSH',
      ),
      NavigationDestination(
        icon: const Icon(Icons.book_outlined),
        selectedIcon: const Icon(Icons.book),
        label: loc.diary,
      ),
      NavigationDestination(
        icon: const Icon(Icons.qr_code_2_outlined),
        selectedIcon: const Icon(Icons.qr_code_2),
        label: loc.qrTool,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: loc.settings,
      ),
    ];

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Image.asset(
                  'assets/icons/icon.png',
                  width: 28,
                  height: 28,
                ),
              ),
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.rss_feed_outlined),
                  selectedIcon: Icon(Icons.rss_feed),
                  label: Text('RSS'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.computer_outlined),
                  selectedIcon: Icon(Icons.computer),
                  label: Text('SSH'),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.book_outlined),
                  selectedIcon: const Icon(Icons.book),
                  label: Text(loc.diary),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.qr_code_2_outlined),
                  selectedIcon: const Icon(Icons.qr_code_2),
                  label: Text(loc.qrTool),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: Text(loc.settings),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: tabs[_currentIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: navItems,
      ),
    );
  }
}
