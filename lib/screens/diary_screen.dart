import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_service.dart';
import '../models/diary_entry.dart';
import '../utils/zebra_paths.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  List<DiaryEntry> _entries = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadEntries() {
    setState(() {
      if (_searchQuery.isNotEmpty) {
        _entries = DatabaseService.searchDiaryEntries(_searchQuery);
      } else {
        _entries = DatabaseService.getAllDiaryEntries();
      }
    });
  }

  void _onSearch(String query) {
    setState(() => _searchQuery = query);
    _loadEntries();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
    _loadEntries();
  }

  String _moodEmoji(String mood) {
    switch (mood) {
      case 'happy': return '😊';
      case 'sad': return '😢';
      case 'angry': return '😠';
      case 'excited': return '🤩';
      default: return '😐';
    }
  }

  String _moodName(String mood, AppLocalizations loc) {
    switch (mood) {
      case 'happy': return loc.diaryMoodHappy;
      case 'sad': return loc.diaryMoodSad;
      case 'angry': return loc.diaryMoodAngry;
      case 'excited': return loc.diaryMoodExcited;
      default: return loc.diaryMoodNeutral;
    }
  }

  Color _moodColor(String mood, ThemeData theme) {
    switch (mood) {
      case 'happy': return Colors.amber;
      case 'sad': return Colors.blue;
      case 'angry': return Colors.red;
      case 'excited': return Colors.purple;
      default: return theme.colorScheme.outline;
    }
  }

  Future<void> _createOrEdit({DiaryEntry? existing}) async {
    final result = await Navigator.push<DiaryEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => DiaryEditScreen(existing: existing),
      ),
    );
    if (result != null) {
      if (existing == null) {
        DatabaseService.insertDiaryEntry(result);
      } else {
        DatabaseService.updateDiaryEntry(result.copyWith(id: existing.id, createdAt: existing.createdAt));
      }
      _loadEntries();
    }
  }

  void _deleteEntry(DiaryEntry entry) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.confirmDelete),
        content: Text(loc.diaryDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () {
              DatabaseService.deleteDiaryEntry(entry.id!);
              Navigator.pop(ctx);
              _loadEntries();
            },
            child: Text(loc.confirm, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final loc = AppLocalizations.of(context);
    try {
      final entries = DatabaseService.getAllDiaryEntries();
      final csv = StringBuffer('title,content,mood,created_at,updated_at\n');
      for (final e in entries) {
        csv.write('${_csvEscape(e.title)},${_csvEscape(e.content)},${e.mood},${e.createdAt.toIso8601String()},${e.updatedAt.toIso8601String()}\n');
      }

      final ts = _timestamp();
      final filename = 'diary_export_$ts.csv';
      final path = await ZebraPaths.filePath('diary', filename);
      final file = File(path);
      await file.writeAsString(csv.toString());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(loc.diaryExportSuccess),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.diaryExportFailed}: $e')),
        );
      }
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _importCsv() async {
    final loc = AppLocalizations.of(context);
    try {
      final path = await ZebraPaths.filePath('diary', 'diary_import.csv');
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.diaryImportPath.replaceAll('{path}', path))),
          );
        }
        return;
      }

      final csvContent = await file.readAsString();
      final lines = csvContent.split('\n').where((l) => l.trim().isNotEmpty).toList();
      var imported = 0;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (i == 0 && line.toLowerCase().contains('title')) continue;

        final parts = _parseCsvLine(line);
        if (parts.length >= 3) {
          final entry = DiaryEntry(
            title: parts[0].trim(),
            content: parts[1].trim(),
            mood: parts[2].trim().isNotEmpty ? parts[2].trim() : 'neutral',
          );
          DatabaseService.insertDiaryEntry(entry);
          imported++;
        }
      }

      _loadEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.diaryImportSuccess} ($imported)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.diaryImportFailed}: $e')),
        );
      }
    }
  }

  String _csvEscape(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    final chars = line.split('');

    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < chars.length && chars[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buffer.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          result.add(buffer.toString());
          buffer.clear();
        } else {
          buffer.write(c);
        }
      }
    }
    result.add(buffer.toString());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomTitleBar.isDesktop
          ? null
          : AppBar(
              title: Text(loc.diary),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: loc.diaryNew,
                  onPressed: () => _createOrEdit(),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'export') _exportCsv();
                    else if (v == 'import') _importCsv();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'export', child: Text(loc.diaryExportCsv)),
                    PopupMenuItem(value: 'import', child: Text(loc.diaryImportCsv)),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: loc.diary,
              showBackButton: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: loc.diaryNew,
                  onPressed: () => _createOrEdit(),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onSelected: (v) {
                    if (v == 'export') _exportCsv();
                    else if (v == 'import') _importCsv();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'export', child: Text(loc.diaryExportCsv)),
                    PopupMenuItem(value: 'import', child: Text(loc.diaryImportCsv)),
                  ],
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '${loc.search}...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              onChanged: _onSearch,
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.book, size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(loc.diaryEmpty, style: theme.textTheme.titleMedium),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _entries.length,
                    itemBuilder: (ctx, i) => _buildEntryCard(_entries[i], theme),
                  ),
          ),
        ],
      ),

    );
  }

  Widget _buildEntryCard(DiaryEntry entry, ThemeData theme) {
    final loc = AppLocalizations.of(context);
    final dateStr = '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')} ${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _createOrEdit(existing: entry),
        onLongPress: () => _deleteEntry(entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_moodEmoji(entry.mood), style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.title.isEmpty ? loc.diaryNoTitle : entry.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _moodColor(entry.mood, theme).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _moodName(entry.mood, AppLocalizations.of(context)),
                      style: TextStyle(
                        fontSize: 10,
                        color: _moodColor(entry.mood, theme),
                      ),
                    ),
                  ),
                ],
              ),
              if (entry.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  entry.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                dateStr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DiaryEditScreen extends StatefulWidget {
  final DiaryEntry? existing;

  const DiaryEditScreen({super.key, this.existing});

  @override
  State<DiaryEditScreen> createState() => _DiaryEditScreenState();
}

class _DiaryEditScreenState extends State<DiaryEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String _mood;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title ?? '');
    _contentController = TextEditingController(text: widget.existing?.content ?? '');
    _mood = widget.existing?.mood ?? 'neutral';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final entry = DiaryEntry(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      mood: _mood,
    );
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    const moods = [
      ('happy', '😊', 'diaryMoodHappy'),
      ('neutral', '😐', 'diaryMoodNeutral'),
      ('sad', '😢', 'diaryMoodSad'),
      ('angry', '😠', 'diaryMoodAngry'),
      ('excited', '🤩', 'diaryMoodExcited'),
    ];

    final title = widget.existing != null ? loc.diaryEdit : loc.diaryNew;
    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: loc.save,
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: title,
              showBackButton: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.check, size: 18),
                  tooltip: loc.save,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: _save,
                ),
              ],
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mood selector
                  Text(loc.diaryMood, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: moods.map((m) {
                      final isSelected = _mood == m.$1;
                      return ChoiceChip(
                        label: Text('${m.$2} ${loc.translate(m.$3)}'),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _mood = m.$1),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: loc.diaryTitle,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Content
                  TextField(
                    controller: _contentController,
                    decoration: InputDecoration(
                      labelText: loc.diaryContent,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 10,
                    minLines: 5,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
