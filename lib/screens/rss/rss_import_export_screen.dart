import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/rss_provider.dart';
import '../../utils/zebra_paths.dart';
import '../../widgets/custom_title_bar.dart';

class RssImportExportScreen extends StatelessWidget {
  const RssImportExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = CustomTitleBar.isDesktop;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(title: Text(loc.importExport)),
      body: Column(
        children: [
          if (isDesktop) CustomTitleBar(title: loc.importExport, showBackButton: true),
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
          title: loc.importFeeds,
          children: [
            _buildActionTile(
              context,
              icon: Icons.file_upload,
              title: loc.rssImportCsv,
              subtitle: loc.rssImportCsvDesc,
              onTap: () => _importCsv(context),
            ),
            _buildActionTile(
              context,
              icon: Icons.file_upload,
              title: loc.rssImportOpml,
              subtitle: loc.rssImportOpmlDesc,
              onTap: () => _importOpml(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: loc.exportFeeds,
          children: [
            _buildActionTile(
              context,
              icon: Icons.file_download,
              title: loc.rssExportCsv,
              subtitle: loc.rssExportCsvDesc,
              onTap: () => _exportCsv(context),
            ),
            _buildActionTile(
              context,
              icon: Icons.file_download,
              title: loc.rssExportOpml,
              subtitle: loc.rssExportOpmlDesc,
              onTap: () => _exportOpml(context),
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

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Future<void> _importCsv(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();
    final provider = context.read<RssProvider>();
    final sources = provider.importFromCsv(content);

    if (context.mounted) {
      final count = provider.importSources(sources);
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssImportComplete.replaceAll('{count}', '$count'))),
      );
    }
  }

  Future<void> _importOpml(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['opml', 'xml'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();
    final provider = context.read<RssProvider>();
    final sources = provider.importFromOpml(content);

    if (context.mounted) {
      final count = provider.importSources(sources);
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.rssImportComplete.replaceAll('{count}', '$count'))),
      );
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final provider = context.read<RssProvider>();
    final csv = provider.exportToCsv();
    final ts = _timestamp();
    await _exportAndShowDialog(context, csv, 'rss_subscriptions_$ts.csv');
  }

  Future<void> _exportOpml(BuildContext context) async {
    final provider = context.read<RssProvider>();
    final opml = provider.exportToOpml();
    final ts = _timestamp();
    await _exportAndShowDialog(context, opml, 'rss_subscriptions_$ts.opml');
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _exportAndShowDialog(BuildContext context, String content, String filename) async {
    final loc = AppLocalizations.of(context);
    try {
      final path = await ZebraPaths.filePath('rss', filename);
      final file = File(path);
      await file.writeAsString(content);

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(loc.rssExportSuccess),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.rssFileSavedTo),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    file.path,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(loc.rssClose),
              ),
              FilledButton(
                onPressed: () {
                  Share.shareXFiles([XFile(file.path)], subject: filename);
                  Navigator.pop(context);
                },
                child: Text(loc.share),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.rssExportFailed}: $e')),
        );
      }
    }
  }
}
