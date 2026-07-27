import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import '../models/ssh_connection.dart';
import '../models/diary_entry.dart';

/// 数据库加密密钥 — release 模式使用。
/// TODO: 可改为从系统密钥链（Keychain / KeyStore）读取以增强安全性。
const _dbEncryptionKey = 'zebra_db_key_2016';

class DatabaseService {
  static Database? _db;
  static String? _dbPath;

  static String get dbPath => _dbPath ?? '';
  static String get dbDirPath => _dbPath != null ? p.dirname(_dbPath!) : '';

  static Future<void> init() async {
    if (_db != null) return;

    final appDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(appDir.path, 'zebra'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }

    _dbPath = p.join(dbDir.path, 'zebra.db');
    _db = sqlite3.open(_dbPath!);

    // Release 构建启用数据库加密，调试模式不加密方便开发
    if (kReleaseMode) {
      _db!.execute("PRAGMA key = '$_dbEncryptionKey'");
    }

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS connections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER DEFAULT 22,
        username TEXT NOT NULL,
        auth_type TEXT DEFAULT 'password',
        password TEXT,
        private_key_path TEXT,
        passphrase TEXT,
        remark TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS diary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        mood TEXT NOT NULL DEFAULT 'neutral',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // ==================== Connections ====================

  static List<SshConnection> getAllConnections() {
    final results = _db!.select('SELECT * FROM connections ORDER BY updated_at DESC');
    return results.map((row) => SshConnection.fromMap(row)).toList();
  }

  static SshConnection? getConnection(int id) {
    final results = _db!.select('SELECT * FROM connections WHERE id = ?', [id]);
    if (results.isEmpty) return null;
    return SshConnection.fromMap(results.first);
  }

  static int insertConnection(SshConnection conn) {
    final stmt = _db!.prepare('''
      INSERT INTO connections (name, host, port, username, auth_type, password, private_key_path, passphrase, remark, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    stmt.execute([
      conn.name,
      conn.host,
      conn.port,
      conn.username,
      conn.authType,
      conn.password,
      conn.privateKeyPath,
      conn.passphrase,
      conn.remark,
      conn.createdAt.toIso8601String(),
      conn.updatedAt.toIso8601String(),
    ]);
    final lastId = _db!.lastInsertRowId;
    stmt.close();
    return lastId;
  }

  static void updateConnection(SshConnection conn) {
    final stmt = _db!.prepare('''
      UPDATE connections
      SET name = ?, host = ?, port = ?, username = ?, auth_type = ?,
          password = ?, private_key_path = ?, passphrase = ?,
          remark = ?, updated_at = ?
      WHERE id = ?
    ''');
    stmt.execute([
      conn.name,
      conn.host,
      conn.port,
      conn.username,
      conn.authType,
      conn.password,
      conn.privateKeyPath,
      conn.passphrase,
      conn.remark,
      conn.updatedAt.toIso8601String(),
      conn.id,
    ]);
    stmt.close();
  }

  static void deleteConnection(int id) {
    final stmt = _db!.prepare('DELETE FROM connections WHERE id = ?');
    stmt.execute([id]);
    stmt.close();
  }

  static void close() {
    _db?.close();
    _db = null;
  }

  // ==================== Diary ====================

  static List<DiaryEntry> getAllDiaryEntries() {
    final results = _db!.select('SELECT * FROM diary ORDER BY created_at DESC');
    return results.map((row) => DiaryEntry.fromMap(row)).toList();
  }

  static DiaryEntry? getDiaryEntry(int id) {
    final results = _db!.select('SELECT * FROM diary WHERE id = ?', [id]);
    if (results.isEmpty) return null;
    return DiaryEntry.fromMap(results.first);
  }

  static int insertDiaryEntry(DiaryEntry entry) {
    final stmt = _db!.prepare('''
      INSERT INTO diary (title, content, mood, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    ''');
    stmt.execute([
      entry.title,
      entry.content,
      entry.mood,
      entry.createdAt.toIso8601String(),
      entry.updatedAt.toIso8601String(),
    ]);
    final lastId = _db!.lastInsertRowId;
    stmt.close();
    return lastId;
  }

  static void updateDiaryEntry(DiaryEntry entry) {
    final stmt = _db!.prepare('''
      UPDATE diary
      SET title = ?, content = ?, mood = ?, updated_at = ?
      WHERE id = ?
    ''');
    stmt.execute([
      entry.title,
      entry.content,
      entry.mood,
      entry.updatedAt.toIso8601String(),
      entry.id,
    ]);
    stmt.close();
  }

  static void deleteDiaryEntry(int id) {
    final stmt = _db!.prepare('DELETE FROM diary WHERE id = ?');
    stmt.execute([id]);
    stmt.close();
  }

  static List<DiaryEntry> searchDiaryEntries(String query) {
    final results = _db!.select(
      "SELECT * FROM diary WHERE title LIKE ? OR content LIKE ? ORDER BY created_at DESC",
      ['%$query%', '%$query%'],
    );
    return results.map((row) => DiaryEntry.fromMap(row)).toList();
  }
}
