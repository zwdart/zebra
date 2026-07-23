import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../providers/rss_provider.dart';
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
          : AppBar(title: const Text('Import/Export')),
      body: Column(
        children: [
          if (isDesktop) CustomTitleBar(title: 'Import/Export', showBackButton: true),
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
          title: 'Import Feeds',
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
          title: 'Export Feeds',
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
    await _shareFile(context, csv, 'rss_subscriptions.csv');
  }

  Future<void> _exportOpml(BuildContext context) async {
    final provider = context.read<RssProvider>();
    final opml = provider.exportToOpml();
    await _shareFile(context, opml, 'rss_subscriptions.opml');
  }

  Future<void> _shareFile(BuildContext context, String content, String filename) async {
    // Use application documents directory (no permissions needed, cross-platform)
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final file = File(p.join(exportDir.path, filename));
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], subject: filename);
  }
}
