import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import '../models/ssh_connection.dart';

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
  }

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
    stmt.dispose();
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
    stmt.dispose();
  }

  static void deleteConnection(int id) {
    final stmt = _db!.prepare('DELETE FROM connections WHERE id = ?');
    stmt.execute([id]);
    stmt.dispose();
  }

  static void close() {
    _db?.dispose();
    _db = null;
  }
}
