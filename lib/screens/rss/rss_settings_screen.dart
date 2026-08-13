import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/rss_provider.dart';
import '../../widgets/custom_title_bar.dart';
import '../../l10n/app_localizations.dart';
import 'server/rss_server_home_screen.dart';

class RssSettingsScreen extends StatefulWidget {
  const RssSettingsScreen({super.key});

  @override
  State<RssSettingsScreen> createState() => _RssSettingsScreenState();
}

class _RssSettingsScreenState extends State<RssSettingsScreen> {
  bool _autoBackupEnabled = false;
  bool _backupBusy = false;
  bool _serverMode = false;
  final TextEditingController _serverUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<RssProvider>();
    provider.isAutoBackupEnabled().then((v) {
      if (mounted) setState(() => _autoBackupEnabled = v);
    });
    _serverMode = provider.serverMode;
    _serverUrlController.text = provider.serverUrl;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildServerModeSection(context),
        const SizedBox(height: 24),
        _buildServerSyncSection(context),
        const SizedBox(height: 24),
        _buildSyncIntervalSection(context),
        const SizedBox(height: 24),
        _buildBackupSection(context),
        const SizedBox(height: 24),
        _buildHistoryCleanupSection(context),
      ],
    );
  }

  Widget _buildServerModeSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();

    return _buildSection(
      context,
      title: loc.rssServerMode,
      children: [
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.cloud_outlined),
                title: Text(loc.rssServerMode),
                subtitle: Text(loc.rssServerModeDesc),
                value: _serverMode,
                onChanged: (value) async {
                  setState(() => _serverMode = value);
                  await provider.setServerMode(value, url: _serverUrlController.text);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(value ? loc.rssServerModeOn : loc.rssServerModeOff)),
                  );
                  if (value) {
                    // 开启服务器模式 → 进入独立的服务器模式主页
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RssServerHomeScreen()),
                    );
                  } else {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
              ),
              if (_serverMode) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: TextField(
                    controller: _serverUrlController,
                    decoration: InputDecoration(
                      labelText: loc.rssServerUrl,
                      hintText: 'https://zebra.dart.xin',
                      prefixIcon: const Icon(Icons.link, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                    onSubmitted: (url) => provider.setServerMode(true, url: url),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 从服务器同步已订阅源的文章到本地库(离线模式可用)。
  /// 按本地已订阅源遍历,url 匹配服务器源后拉取最近 N 天文章。
  Widget _buildServerSyncSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();

    return _buildSection(
      context,
      title: loc.rssSyncToLocal,
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: Text(loc.rssSyncWindow),
                subtitle: Text(loc.rssServerModeDesc),
                trailing: DropdownButton<int>(
                  value: provider.serverSyncDays,
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('7 天')),
                    DropdownMenuItem(value: 30, child: Text('30 天')),
                  ],
                  onChanged: (v) {
                    if (v != null) provider.setServerSyncDays(v);
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final count = await provider.syncServerSourcesToLocal(
                        days: provider.serverSyncDays,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(loc.rssSyncToLocalDone(count))),
                      );
                    },
                    icon: const Icon(Icons.download),
                    label: Text(loc.rssSyncToLocal),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackupSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final provider = context.read<RssProvider>();

    return _buildSection(
      context,
      title: loc.rssAutoBackup,
      children: [
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.backup_outlined),
                title: Text(loc.rssAutoBackup),
                subtitle: Text(loc.rssAutoBackupDesc),
                value: _autoBackupEnabled,
                onChanged: (value) async {
                  setState(() => _autoBackupEnabled = value);
                  await provider.setAutoBackupEnabled(value);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: Text(loc.rssBackupNow),
                subtitle: Text(loc.rssBackupNowDesc),
                enabled: !_backupBusy,
                onTap: () async {
                  setState(() => _backupBusy = true);
                  final ok = await provider.backupNow();
                  if (!mounted) return;
                  setState(() => _backupBusy = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? loc.rssBackupDone : loc.rssBackupFailed)),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncIntervalSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final provider = context.watch<RssProvider>();
    final currentMin = provider.syncIntervalMinutes;
    const options = [15, 30, 60, 120];

    return _buildSection(
      context,
      title: loc.rssSyncInterval,
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text(loc.rssSyncInterval),
                subtitle: Text(loc.rssSyncIntervalDesc.replaceAll('{min}', '$currentMin')),
                trailing: DropdownButton<int>(
                  value: currentMin,
                  underline: const SizedBox(),
                  items: options.map((min) {
                    return DropdownMenuItem(
                      value: min,
                      child: Text(loc.rssSyncIntervalMin.replaceAll('{min}', '$min')),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null && value != currentMin) {
                      provider.setSyncIntervalMinutes(value);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryCleanupSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return _buildSection(
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
