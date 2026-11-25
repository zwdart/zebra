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
  static Database get rawDb => _db!;

  static void _openDb({required bool withKey}) {
    _db = sqlite3.open(_dbPath!);
    if (withKey) {
      _db!.execute("PRAGMA key = '$_dbEncryptionKey'");
    }
  }

  static void _verifyDb() {
    final check = _db!
        .select('PRAGMA quick_check')
        .first
        .values
        .first
        .toString();
    if (check != 'ok') {
      throw StateError('database corrupt: $check');
    }
  }

  static void _backupCorruptDb() {
    try {
      final bak = '$_dbPath.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      File(_dbPath!).copySync(bak);
    } catch (_) {}
    try {
      File(_dbPath!).deleteSync();
    } catch (_) {}
  }

  static Future<void> init() async {
    if (_db != null) return;

    final appDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(appDir.path, 'zebra'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }

    _dbPath = p.join(dbDir.path, 'zebra.db');

    // 优先按当前构建模式打开；若库是用另一种模式（加密/未加密）创建的，
    // 自动切换后再试，避免 debug/release 混用同一份数据时无法启动。
    try {
      _openDb(withKey: kReleaseMode);
      _verifyDb();
    } catch (_) {
      _db?.close();
      _db = null;
      try {
        _openDb(withKey: !kReleaseMode);
        _verifyDb();
      } catch (e) {
        // 两种模式都打不开：备份坏库后按当前模式重建
        debugPrint('Database init failed ($e), backing up and rebuilding');
        _db?.close();
        _db = null;
        _backupCorruptDb();
        _openDb(withKey: kReleaseMode);
        _verifyDb();
      }
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

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL,
        peer_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'text',
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_me INTEGER NOT NULL DEFAULT 0,
        is_read INTEGER NOT NULL DEFAULT 0
      )
    ''');

    _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_messages_peer
      ON chat_messages(peer_id, timestamp DESC)
    ''');

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS chat_peers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_id TEXT NOT NULL UNIQUE,
        peer_name TEXT NOT NULL,
        last_message TEXT,
        last_time TEXT,
        unread_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS lan_conversations (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL DEFAULT 'direct',
        peer_id TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        owner TEXT NOT NULL DEFAULT '',
        members TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        unread INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        muted INTEGER NOT NULL DEFAULT 0,
        draft TEXT NOT NULL DEFAULT ''
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS lan_messages (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL,
        conv_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL DEFAULT 'text',
        text TEXT NOT NULL DEFAULT '',
        file_name TEXT,
        file_size INTEGER NOT NULL DEFAULT 0,
        file_mime TEXT,
        file_url TEXT,
        file_token TEXT,
        file_path TEXT,
        file_width INTEGER NOT NULL DEFAULT 0,
        file_height INTEGER NOT NULL DEFAULT 0,
        sent_at INTEGER NOT NULL DEFAULT 0,
        edited_at INTEGER,
        status TEXT NOT NULL DEFAULT '',
        delivered INTEGER NOT NULL DEFAULT 0,
        read INTEGER NOT NULL DEFAULT 0,
        recalled INTEGER NOT NULL DEFAULT 0,
        UNIQUE(conv_id, id)
      )
    ''');
    _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_lan_messages_conv
      ON lan_messages(conv_id, sent_at, seq)
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS lan_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ==================== Connections ====================

  static List<SshConnection> getAllConnections() {
    final results = _db!.select(
      'SELECT * FROM connections ORDER BY updated_at DESC',
    );
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

  // ==================== Chat Messages ====================

  static List<Map<String, dynamic>> getChatMessages(
    String peerId, {
    int page = 1,
    int size = 50,
  }) {
    final offset = (page - 1) * size;
    final results = _db!.select(
      'SELECT * FROM chat_messages WHERE peer_id = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?',
      [peerId, size, offset],
    );
    return results.map((r) {
      final map = <String, dynamic>{};
      for (final col in r.keys) {
        map[col] = r[col];
      }
      return map;
    }).toList();
  }

  static void insertChatMessage(Map<String, dynamic> msg) {
    final stmt = _db!.prepare('''
      INSERT INTO chat_messages (message_id, peer_id, sender_id, sender_name, type, content, timestamp, is_me, is_read)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    stmt.execute([
      msg['message_id'],
      msg['peer_id'],
      msg['sender_id'],
      msg['sender_name'],
      msg['type'],
      msg['content'],
      msg['timestamp'],
      msg['is_me'] ?? 0,
      msg['is_read'] ?? 0,
    ]);
    stmt.close();
  }

  static void updateChatPeerLastMessage(
    String peerId,
    String peerName,
    String lastMessage,
    String lastTime,
  ) {
    final stmt = _db!.prepare('''
      INSERT INTO chat_peers (peer_id, peer_name, last_message, last_time, unread_count)
      VALUES (?, ?, ?, ?, 1)
      ON CONFLICT(peer_id) DO UPDATE SET
        peer_name = excluded.peer_name,
        last_message = excluded.last_message,
        last_time = excluded.last_time,
        unread_count = unread_count + 1
    ''');
    stmt.execute([peerId, peerName, lastMessage, lastTime]);
    stmt.close();
  }

  static void markChatPeerRead(String peerId) {
    _db!.execute('UPDATE chat_peers SET unread_count = 0 WHERE peer_id = ?', [
      peerId,
    ]);
  }

  static List<Map<String, dynamic>> getChatPeers() {
    final results = _db!.select(
      'SELECT * FROM chat_peers ORDER BY last_time DESC',
    );
    return results.map((r) {
      final map = <String, dynamic>{};
      for (final col in r.keys) {
        map[col] = r[col];
      }
      return map;
    }).toList();
  }

  static void deleteChatMessages(String peerId) {
    _db!.execute('DELETE FROM chat_messages WHERE peer_id = ?', [peerId]);
    _db!.execute('DELETE FROM chat_peers WHERE peer_id = ?', [peerId]);
  }

  /// 按消息 ID 删除与某 peer 的单条/多条消息(不删除会话本身)
  static void deleteChatMessagesByIds(String peerId, List<String> ids) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    _db!.execute(
      'DELETE FROM chat_messages WHERE peer_id = ? AND message_id IN ($placeholders)',
      [peerId, ...ids],
    );
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
