import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database_service.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.settings),
      ),
      body: ListView(
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
            trailing: const Icon(Icons.folder_open),
            onTap: () => _openDatabaseDirectory(context),
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
        title: const Text('Language'),
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
}
