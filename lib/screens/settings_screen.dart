import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_service.dart';
import '../utils/unique_id.dart';
import '../utils/zebra_paths.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/update_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/rss_provider.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'about_screen.dart';
import 'rss/rss_explore_screen.dart';
import '../features/qr_tool/screens/qr_tool_screen.dart';
import 'update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showApiServer = false;

  void toggleApiServerVisibility() {
    setState(() {
      _showApiServer = !_showApiServer;
    });
    // 切换 API Server 显示时，清除版本更新的7天跳过计时器
    UpdateService.clearSkipUpdateTime();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text(loc.settings),
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(title: loc.settings, showBackButton: false),
          Expanded(
            child: ListView(
              children: [
                _buildSectionHeader(context, loc.language),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(loc.language),
                  subtitle: Text(LocaleProvider.localeNames[Localizations.localeOf(context).languageCode] ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showLanguagePicker(context),
                ),
                const Divider(),
                _buildSectionHeader(context, loc.theme),
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: Text(loc.selectThemeColor),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showColorPicker(context),
                ),
                ListTile(
                  leading: const Icon(Icons.brightness_6),
                  title: Text(loc.theme),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showThemeModePicker(context),
                ),
                const Divider(),
                _buildSectionHeader(context, loc.more),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(loc.blog),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RssExploreScreen(initialTab: 2)),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: Text(loc.discover),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RssExploreScreen(initialTab: 1)),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(loc.qrTool),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QrToolScreen()),
                    );
                  },
                ),
                const Divider(),
                if (_showApiServer) ...[
                  _buildSectionHeader(context, loc.api),
                  ListTile(
                    leading: const Icon(Icons.cloud),
                    title: Text(loc.apiServer),
                    subtitle: Text(
                      UpdateService.apiBaseUrl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showApiUrlDialog(context),
                  ),
                  const Divider(),
                ],
                const Divider(),
                _buildSectionHeader(context, loc.storage),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: Text(loc.storageInfo),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showStorageInfoDialog(context),
                ),
                if (Platform.isLinux) ...[
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: Text(loc.uninstallFromSystem, style: const TextStyle(color: Colors.red)),
                    onTap: () => _uninstallFromSystem(context),
                  ),
                ],
                const Divider(),
                _buildSectionHeader(context, loc.about),
                Consumer<UpdateProvider>(
                  builder: (context, updateProvider, _) {
                    return ListTile(
                      leading: Icon(
                        updateProvider.state == UpdateState.hasUpdate
                            ? Icons.system_update
                            : Icons.update,
                        color: updateProvider.state == UpdateState.hasUpdate
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      title: Text(loc.checkForUpdates),
                      subtitle: updateProvider.state == UpdateState.hasUpdate
                          ? Text(
                              '${loc.newVersionAvailable}: ${updateProvider.versionInfo?.version ?? ""}',
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            )
                          : null,
                      trailing: updateProvider.state == UpdateState.checking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: updateProvider.state == UpdateState.checking
                          ? null
                          : () => _checkForUpdates(context),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(loc.aboutUs),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AboutScreen(
                          onToggleApiServer: toggleApiServerVisibility,
                        ),
                      ),
                    );
                  },
                ),
                _buildUniqueIdTile(context, loc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(context).language),
        children: LocaleProvider.localeNames.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () {
              context.read<LocaleProvider>().setLocale(Locale(e.key));
              Navigator.pop(ctx);
            },
            child: Text(e.value),
          );
        }).toList(),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).selectThemeColor),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppTheme.themeColors.map((tc) {
            final isSelected = Theme.of(context).colorScheme.primary == tc.$2;
            return GestureDetector(
              onTap: () {
                context.read<ThemeProvider>().setSeedColor(tc.$2);
                Navigator.pop(ctx);
              },
              child: SizedBox(
                width: 48,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? tc.$2 : Colors.grey.shade400,
                      width: isSelected ? 3 : 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ClipOval(
                      child: ColoredBox(color: tc.$2),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showThemeModePicker(BuildContext context) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.theme),
        children: [
          SimpleDialogOption(
            onPressed: () {
              context.read<ThemeProvider>().setThemeMode(ThemeMode.light);
              Navigator.pop(ctx);
            },
            child: Text(loc.lightMode),
          ),
          SimpleDialogOption(
            onPressed: () {
              context.read<ThemeProvider>().setThemeMode(ThemeMode.dark);
              Navigator.pop(ctx);
            },
            child: Text(loc.darkMode),
          ),
          SimpleDialogOption(
            onPressed: () {
              context.read<ThemeProvider>().setThemeMode(ThemeMode.system);
              Navigator.pop(ctx);
            },
            child: Text(loc.systemMode),
          ),
        ],
      ),
    );
  }

  Widget _buildUniqueIdTile(BuildContext context, AppLocalizations loc) {
    return FutureBuilder<String>(
      future: UniqueId.get(),
      builder: (ctx, snapshot) {
        final id = snapshot.data ?? '...';
        return ListTile(
          leading: const Icon(Icons.fingerprint),
          title: Text(loc.uniqueId),
          subtitle: Text(
            id,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.copy, size: 20),
          onTap: () {
            Clipboard.setData(ClipboardData(text: id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(loc.uniqueIdCopied)),
            );
          },
        );
      },
    );
  }

  void _shareAllDatabases(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final dirPath = DatabaseService.dbDirPath;
    if (dirPath.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.databaseDirNotFound)),
        );
      }
      return;
    }

    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.databaseDirNotFound)),
        );
      }
      return;
    }

    final dbFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList();
    if (dbFiles.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.noDatabaseFiles)),
        );
      }
      return;
    }

    final xFiles = dbFiles.map((f) => XFile(f.path)).toList();
    await Share.shareXFiles(xFiles, text: loc.shareDatabases);
  }

  void _checkForUpdates(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDialog(isManualCheck: true),
    );
  }

  void _showApiUrlDialog(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController(text: UpdateService.apiBaseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.apiServer),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: loc.apiBaseUrl,
            hintText: 'https://zebra.dart.xin',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () async {
              await UpdateService.resetApiBaseUrl();
              controller.text = UpdateService.apiBaseUrl;
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.apiUrlResetDefault)),
                );
              }
            },
            child: Text(loc.resetToDefault),
          ),
          TextButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await UpdateService.setApiBaseUrl(url);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(loc.apiUrlUpdated(url))),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
  }

  void _showStorageInfoDialog(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    // 异步获取路径
    final tempDir = Directory.systemTemp;
    final docDir = await getApplicationDocumentsDirectory();
    final rssDir = await ZebraPaths.rss;
    final cachePath = tempDir.path;
    final dbPath = DatabaseService.dbDirPath;
    final localStoragePath = docDir.path;
    final rssPath = rssDir.path;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.storage, size: 24),
            const SizedBox(width: 8),
            Text(loc.storageInfo),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ========== 系统信息 ==========
              Text(
                loc.systemInfo,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              _infoRow(loc.operatingSystem, '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
              const SizedBox(height: 4),
              _infoRow(loc.processorCores, '${Platform.numberOfProcessors}'),
              const SizedBox(height: 4),
              _infoRow(loc.hostName, Platform.localHostname),
              const Divider(height: 24),
              // ========== 路径信息 ==========
              Text(
                loc.databasePathLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              _pathTile(loc.cachePath, cachePath),
              _pathTile(loc.databasePathLabel, dbPath),
              _pathTile(loc.localStoragePath, localStoragePath),
              _pathTile(loc.rssDownloadPath, rssPath),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _shareAllDatabases(context);
            },
            child: Text(loc.shareDatabase),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmClearRunningData(context);
            },
            child: Text(loc.clearRunningData),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmClearAllData(context);
            },
            child: Text(
              loc.clearAllData,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).close),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    );
  }

  Widget _pathTile(String label, String path) {
    return InkWell(
      onTap: path.isNotEmpty ? () => _openDirectory(path) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.folder_open, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path.isNotEmpty ? path : '(empty)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDirectory(String path) async {
    final loc = AppLocalizations.of(context);
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.errorWithDetail('$e'))),
        );
      }
    }
  }

  void _confirmClearRunningData(BuildContext context) {
    final loc = AppLocalizations.of(context);
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.clearRunningData),
        content: Text(loc.clearRunningDataMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.confirm),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true || !context.mounted) return;
      try {
        // 清理系统临时目录下的 zebra 相关缓存
        final tempDir = Directory.systemTemp;
        final zebraTemp = Directory('${tempDir.path}/zebra');
        if (zebraTemp.existsSync()) {
          zebraTemp.deleteSync(recursive: true);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.clearSuccess)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.clearFailed}: $e')),
          );
        }
      }
    });
  }

  void _confirmClearAllData(BuildContext context) {
    final loc = AppLocalizations.of(context);
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.clearAllData),
        content: Text(loc.clearAllDataMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.confirm, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true || !context.mounted) return;
      try {
        // 清理临时目录缓存
        final tempDir = Directory.systemTemp;
        final zebraTemp = Directory('${tempDir.path}/zebra');
        if (zebraTemp.existsSync()) {
          zebraTemp.deleteSync(recursive: true);
        }

        // 删除数据库文件（先关闭连接，避免句柄指向已删除文件）
        DatabaseService.close();
        final dbFile = File(DatabaseService.dbPath);
        if (dbFile.existsSync()) {
          dbFile.deleteSync();
        }

        // 删除应用支持目录下的数据
        final appDir = await getApplicationSupportDirectory();
        final zebraData = Directory('${appDir.path}/zebra');
        if (zebraData.existsSync()) {
          zebraData.deleteSync(recursive: true);
        }

        // 重建空数据库，并刷新各 Provider 的内存数据
        await DatabaseService.init();
        if (context.mounted) {
          context.read<ConnectionProvider>().loadConnections();
          context.read<DiaryProvider>().loadEntries();
          context.read<RssProvider>().loadFeedSources();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.clearSuccess)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.clearFailed}: $e')),
          );
        }
      }
    });
  }

  String? _findPackerBinary() {
    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final candidates = [
      '$home/.local/bin/zebra',
      '${Directory.current.path}/zebra',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  void _uninstallFromSystem(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.confirmUninstall),
        content: Text(loc.confirmUninstallMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.confirm, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final packer = _findPackerBinary();
    if (packer == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.uninstallFailed)),
        );
      }
      return;
    }

    final result = await Process.run(packer, ['--uninstall']);
    if (context.mounted) {
      if (result.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.uninstallSuccess)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.uninstallFailed}: ${result.stderr}')),
        );
      }
    }
  }
}
