import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  final String strEmail = 'zebra@dart.xin';
  final String strWebUrl = 'http://zebra.dart.xin';
  final String strShop = 'https://fone.taobao.com/';

  static String _getBuildTime() {
    final env = Platform.environment["BUILD_TIME"];
    if (env != null && env.isNotEmpty) return env;
    final define = String.fromEnvironment("BUILD_TIME", defaultValue: "");
    if (define.isNotEmpty) return define;
    return "unknown";
  }


  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text(loc.aboutUs),
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(title: loc.aboutUs, showBackButton: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 32),
                Icon(
                  Icons.terminal,
                  size: 72,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Zebra SSH',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isZh ? '友好的 SSH 客户端' : 'A Helpful SSH Client',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${loc.version}: 1.0.0',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${loc.buildTime}: ${_getBuildTime()}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                Card(
                  child: Column(
                    children: [
                      _buildInfoTile(
                        context,
                        icon: Icons.code,
                        title: loc.developer,
                        subtitle: 'Zebra',
                      ),
                      const Divider(height: 1),
                      _buildInfoTile(
                        context,
                        icon: Icons.email_outlined,
                        title: loc.contactUs,
                        subtitle: strEmail,
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: strEmail));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isZh ? '邮箱已复制' : 'Email copied')),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      _buildInfoTile(
                        context,
                        icon: Icons.language,
                        title: loc.website,
                        subtitle: strWebUrl,
                        onTap: () => launchUrl(Uri.parse(strWebUrl)),
                      ),
                      const Divider(height: 1),
                      _buildInfoTile(
                        context,
                        icon: Icons.storefront,
                        title: loc.shop,
                        subtitle: strShop,
                        onTap: () => launchUrl(Uri.parse(strShop)),
                      ),
                      const Divider(height: 1),
                      _buildInfoTile(
                        context,
                        icon: Icons.source,
                        title: loc.openSourceLicenses,
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'Zebra SSH',
                          applicationVersion: '1.0.0',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isZh
                          ? 'Zebra SSH 是一款跨平台 SSH 客户端，支持终端、SFTP 文件管理、服务器监控、进程管理和磁盘清理等功能。支持 Linux、macOS、Windows、Android 和 iOS。'
                          : 'Zebra SSH is a cross-platform SSH client with terminal, SFTP file management, server monitoring, process management and disk cleanup features. Supports Linux, macOS, Windows, Android and iOS.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}
