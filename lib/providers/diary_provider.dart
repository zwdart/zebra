import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../database/database_service.dart';
import '../models/diary_entry.dart';
import '../utils/zebra_paths.dart';

/// 日记页面状态管理
class DiaryProvider extends ChangeNotifier {
  List<DiaryEntry> _entries = [];
  String _searchQuery = '';

  List<DiaryEntry> get entries => List.unmodifiable(_entries);
  String get searchQuery => _searchQuery;

  /// 加载日记列表
  void loadEntries() {
    if (_searchQuery.isNotEmpty) {
      _entries = DatabaseService.searchDiaryEntries(_searchQuery);
    } else {
      _entries = DatabaseService.getAllDiaryEntries();
    }
    notifyListeners();
  }

  /// 搜索
  void onSearch(String query) {
    _searchQuery = query;
    loadEntries();
  }

  /// 清除搜索
  void clearSearch() {
    _searchQuery = '';
    loadEntries();
  }

  /// 创建或编辑后刷新
  void refreshAfterEdit() {
    loadEntries();
  }

  /// 删除日记
  void deleteEntry(DiaryEntry entry) {
    DatabaseService.deleteDiaryEntry(entry.id!);
    loadEntries();
  }

  /// 插入日记
  void insertEntry(DiaryEntry entry) {
    DatabaseService.insertDiaryEntry(entry);
    loadEntries();
  }

  /// 更新日记
  void updateEntry(DiaryEntry entry) {
    DatabaseService.updateDiaryEntry(entry);
    loadEntries();
  }

  /// 导出 CSV
  Future<String?> exportCsv() async {
    try {
      final entries = DatabaseService.getAllDiaryEntries();
      final csv = StringBuffer('title,content,mood,created_at,updated_at\n');
      for (final e in entries) {
        csv.write('${_csvEscape(e.title)},'
            '${_csvEscape(e.content)},'
            '${e.mood},'
            '${e.createdAt.toIso8601String()},'
            '${e.updatedAt.toIso8601String()}\n');
      }

      final now = DateTime.now();
      final ts = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final filename = 'diary_export_$ts.csv';
      final path = await ZebraPaths.filePath('diary', filename);
      final file = File(path);
      await file.writeAsString(csv.toString());
      return file.path;
    } catch (e) {
      return null;
    }
  }

  /// 导入 CSV
  Future<int?> importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return null;

    try {
      final file = File(result.files.first.path!);
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

      loadEntries();
      return imported;
    } catch (_) {
      return null;
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
}
