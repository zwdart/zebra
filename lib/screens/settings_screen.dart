import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_service.dart';
import '../utils/unique_id.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'about_screen.dart';
import 'blog_screen.dart';
import 'discovery_screen.dart';
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
                _buildSectionHeader(context, 'Database'),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: Text('Database Path'),
                  subtitle: Text(
                    DatabaseService.dbDirPath,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: _buildDatabaseTrailing(context),
                  onTap: () => _onDatabaseTap(context),
                ),
                const Divider(),
                if (_showApiServer) ...[
                  _buildSectionHeader(context, 'API'),
                  ListTile(
                    leading: const Icon(Icons.cloud),
                    title: const Text('API Server'),
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
                _buildSectionHeader(context, loc.more),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(loc.blog),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BlogScreen()),
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
                      MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                    );
                  },
                ),
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
                if (Platform.isLinux) ...[
                  const Divider(),
                  _buildSectionHeader(context, loc.systemIntegration),
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: Text(loc.uninstallFromSystem, style: const TextStyle(color: Colors.red)),
                    onTap: () => _uninstallFromSystem(context),
                  ),
                ],
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

  void _openDatabaseDirectory(BuildContext context) async {
    final path = DatabaseService.dbDirPath;
    if (path.isEmpty) return;

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
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
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

  Widget? _buildDatabaseTrailing(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      return IconButton(
        icon: const Icon(Icons.share),
        tooltip: AppLocalizations.of(context).shareDatabase,
        onPressed: () => _shareDatabase(context),
      );
    }
    return const Icon(Icons.folder_open);
  }

  void _onDatabaseTap(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      _shareDatabase(context);
    } else {
      _openDatabaseDirectory(context);
    }
  }

  void _shareDatabase(BuildContext context) async {
    final dbFile = File(DatabaseService.dbPath);
    if (!await dbFile.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database file not found')),
        );
      }
      return;
    }
    await Share.shareXFiles([XFile(dbFile.path)], text: 'zebra.db');
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
        title: const Text('API Server'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'API Base URL',
            hintText: 'https://zebra.dart.xin',
            border: OutlineInputBorder(),
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
                  SnackBar(content: Text('API URL reset to default')),
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
                    SnackBar(content: Text('API URL updated: $url')),
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
