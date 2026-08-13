import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/rss_provider.dart';
import '../../../services/rss_api_service.dart';
import '../../../widgets/custom_title_bar.dart';

/// 服务器模式独立设置页：服务器地址 / 连接测试 / 立即抓取 / 抓取状态 / 未读汇总 / 关闭模式。
class RssServerSettingsScreen extends StatefulWidget {
  const RssServerSettingsScreen({super.key});

  @override
  State<RssServerSettingsScreen> createState() => _RssServerSettingsScreenState();
}

class _RssServerSettingsScreenState extends State<RssServerSettingsScreen> {
  late final TextEditingController _urlController;
  bool _busy = false;
  String? _connectionResult; // null=未测试, 'ok'=成功, 否则失败信息
  Map<String, dynamic>? _syncStatus;
  int _totalUnread = 0;
  int _sourceCount = 0;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RssProvider>();
    _urlController = TextEditingController(text: provider.serverUrl);
    _loadStats();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final unread = await RssApiService.getServerUnreadSummary();
    final status = await RssApiService.getServerSyncStatus();
    final sources = await RssApiService.getSources(size: 100);
    if (!mounted) return;
    setState(() {
      _totalUnread = (unread?['total_unread'] as int?) ?? 0;
      _syncStatus = status;
      _sourceCount = sources?.sources.length ?? 0;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _connectionResult = null;
    });
    final url = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) {
      setState(() {
        _busy = false;
        _connectionResult = 'fail';
      });
      return;
    }
    // 临时切换到待测地址做连通性校验（成功才持久化开启，失败不影响现有状态）
    final prevBaseUrl = RssApiService.rssServerBaseUrl;
    RssApiService.rssServerBaseUrl = url;
    final ok = await RssApiService.getServerSyncStatus() != null ||
        await RssApiService.getServerUnreadSummary() != null;
    if (ok) {
      // 校验成功：持久化 server 模式并保持该基址
      await context.read<RssProvider>().setServerMode(true, url: url);
    } else {
      // 校验失败：恢复原基址，不改变模式状态
      RssApiService.rssServerBaseUrl = prevBaseUrl;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _connectionResult = ok ? 'ok' : 'fail';
    });
    if (ok) await _loadStats();
  }

  Future<void> _triggerFetch() async {
    setState(() => _busy = true);
    final ok = await RssApiService.triggerServerSync();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? AppLocalizations.of(context).rssServerFetchTriggered : AppLocalizations.of(context).rssServerFetchFailed)),
    );
    await _loadStats();
  }

  Future<void> _disableServerMode() async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.rssServerDisable),
        content: Text(loc.rssServerDisableConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<RssProvider>().setServerMode(false);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDesktop = CustomTitleBar.isDesktop;

    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: Text(loc.rssServerSettings)),
      body: Column(
        children: [
          if (isDesktop) CustomTitleBar(title: loc.rssServerSettings, showBackButton: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildConnectionSection(context),
                const SizedBox(height: 24),
                _buildStatusSection(context),
                const SizedBox(height: 24),
                _buildDisableSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 连接与地址 ====================

  Widget _buildConnectionSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.rssServerConnection, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: loc.rssServerUrl,
                    hintText: 'https://zebra.dart.xin',
                    prefixIcon: const Icon(Icons.link, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _testConnection,
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: Text(loc.rssServerTestConnection),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _triggerFetch,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(loc.rssServerFetchNow),
                      ),
                    ),
                  ],
                ),
                if (_connectionResult != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _connectionResult == 'ok' ? Icons.check_circle : Icons.error,
                        size: 18,
                        color: _connectionResult == 'ok' ? Colors.green : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _connectionResult == 'ok' ? loc.rssServerConnectionOk : loc.rssServerConnectionFail,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==================== 状态汇总 ====================

  Widget _buildStatusSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = _syncStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.rssServerStatus, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.rss_feed, size: 20),
                title: Text(loc.rssServerSourceCount),
                trailing: Text('$_sourceCount', style: theme.textTheme.titleMedium),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined, size: 20),
                title: Text(loc.rssServerTotalUnread),
                trailing: Text('$_totalUnread', style: theme.textTheme.titleMedium),
              ),
              if (status != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sync, size: 20),
                  title: Text(loc.rssServerPending),
                  trailing: Text('${status['pending'] ?? 0}', style: theme.textTheme.titleMedium),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, size: 20),
                  title: Text(loc.rssServerPaused),
                  trailing: Text('${status['failed'] ?? 0}', style: theme.textTheme.titleMedium),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history, size: 20),
                  title: Text(loc.rssServerLastFetch),
                  trailing: Text(
                    (status['last_fetch_at'] as String?) ?? '-',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 关闭模式 ====================

  Widget _buildDisableSection(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.rssServerMode, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined, color: theme.colorScheme.error),
            title: Text(loc.rssServerDisable, style: TextStyle(color: theme.colorScheme.error)),
            subtitle: Text(loc.rssServerDisableDesc),
            onTap: _disableServerMode,
          ),
        ),
      ],
    );
  }
}
