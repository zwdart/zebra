import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/rss_provider.dart';
import '../../widgets/custom_title_bar.dart';
import '../../l10n/app_localizations.dart';

class RssSettingsScreen extends StatelessWidget {
  const RssSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;

    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: Text(loc.rssSettings)),
      body: Column(
        children: [
          if (isDesktop) CustomTitleBar(title: loc.rssSettings, showBackButton: true),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSection(
          context,
          title: loc.rssHistoryCleanup,
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(loc.rssClean7Days),
                    subtitle: Text(loc.rssClean7DaysDesc),
                    onTap: () => _clearHistory(context, days: 7),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(loc.rssClean30Days),
                    subtitle: Text(loc.rssClean30DaysDesc),
                    onTap: () => _clearHistory(context, days: 30),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                    title: Text(loc.rssCleanAll, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    subtitle: Text(loc.rssCleanAllDesc),
                    onTap: () => _clearAllArticles(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  void _clearHistory(BuildContext context, {required int days}) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssCleanConfirm),
        content: Text(loc.rssCleanDaysConfirm.replaceAll('{days}', '$days')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              final before = DateTime.now().subtract(Duration(days: days));
              context.read<RssProvider>().clearHistory(before: before);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.rssCleanedAll.replaceAll('{days}', '$days'))),
              );
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  void _clearAllArticles(BuildContext context) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssCleanConfirm),
        content: Text(loc.rssCleanAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<RssProvider>().clearHistory();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.rssCleanedAll.replaceAll('{days}', ''))),
              );
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }
}
