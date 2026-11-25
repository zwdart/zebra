import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../../database/database_service.dart';
import '../models/lan_models.dart';

class LanStore {
  Database get _db => DatabaseService.rawDb;

  List<Conversation> loadConversations() {
    final rows = _db.select('SELECT * FROM lan_conversations');
    return rows.map((r) {
      List<String> members = [];
      try {
        final raw = jsonDecode('${r['members']}');
        if (raw is List) members = raw.map((e) => '$e').toList();
      } catch (_) {}
      return Conversation(
        id: '${r['id']}',
        kind: '${r['kind']}' == 'group' ? ConvKind.group : ConvKind.direct,
        peerId: '${r['peer_id']}',
        title: '${r['title']}',
        owner: '${r['owner']}',
        members: members,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (r['created_at'] as int?) ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (r['updated_at'] as int?) ?? 0,
        ),
        unread: (r['unread'] as int?) ?? 0,
        pinned: ((r['pinned'] as int?) ?? 0) != 0,
        muted: ((r['muted'] as int?) ?? 0) != 0,
        draft: '${r['draft']}',
      );
    }).toList();
  }

  void saveConversation(Conversation c) {
    final stmt = _db.prepare('''
      INSERT INTO lan_conversations
        (id, kind, peer_id, title, owner, members, created_at, updated_at,
         unread, pinned, muted, draft)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        kind = excluded.kind,
        peer_id = excluded.peer_id,
        title = excluded.title,
        owner = excluded.owner,
        members = excluded.members,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        unread = excluded.unread,
        pinned = excluded.pinned,
        muted = excluded.muted,
        draft = excluded.draft
    ''');
    stmt.execute([
      c.id,
      c.kind.name,
      c.peerId,
      c.title,
      c.owner,
      jsonEncode(c.members),
      c.createdAt.millisecondsSinceEpoch,
      c.updatedAt.millisecondsSinceEpoch,
      c.unread,
      c.pinned ? 1 : 0,
      c.muted ? 1 : 0,
      c.draft,
    ]);
    stmt.close();
  }

  void deleteConversation(String id) {
    _db.execute('DELETE FROM lan_messages WHERE conv_id = ?', [id]);
    _db.execute('DELETE FROM lan_conversations WHERE id = ?', [id]);
  }

  void deleteMessage(String convId, String id) {
    _db.execute('DELETE FROM lan_messages WHERE conv_id = ? AND id = ?', [
      convId,
      id,
    ]);
  }

  void deleteMessages(String convId, List<String> ids) {
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    _db.execute(
      'DELETE FROM lan_messages WHERE conv_id = ? AND id IN ($marks)',
      [convId, ...ids],
    );
  }

  void clearAllHistory() {
    _db.execute('DELETE FROM lan_messages');
  }

  List<Message> loadMessages(String convId) {
    final rows = _db.select(
      'SELECT * FROM lan_messages WHERE conv_id = ? ORDER BY sent_at, seq',
      [convId],
    );
    return rows.map(_fromRow).toList();
  }

  Message _fromRow(Row r) {
    MessageKind kind;
    switch ('${r['kind']}') {
      case 'image':
        kind = MessageKind.image;
        break;
      case 'file':
        kind = MessageKind.file;
        break;
      case 'system':
        kind = MessageKind.system;
        break;
      default:
        kind = MessageKind.text;
    }
    final fileName = r['file_name'] as String?;
    FileMeta? file;
    if (fileName != null) {
      file = FileMeta(
        name: fileName,
        size: (r['file_size'] as int?) ?? 0,
        mime: '${r['file_mime'] ?? ''}',
        url: '${r['file_url'] ?? ''}',
        token: '${r['file_token'] ?? ''}',
        path: '${r['file_path'] ?? ''}',
        width: (r['file_width'] as int?) ?? 0,
        height: (r['file_height'] as int?) ?? 0,
      );
    }
    final edited = r['edited_at'] as int?;
    return Message(
      id: '${r['id']}',
      convId: '${r['conv_id']}',
      senderId: '${r['sender_id']}',
      senderName: '${r['sender_name']}',
      kind: kind,
      text: '${r['text']}',
      file: file,
      sentAt: DateTime.fromMillisecondsSinceEpoch((r['sent_at'] as int?) ?? 0),
      editedAt: edited == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(edited),
      status: '${r['status']}',
      delivered: ((r['delivered'] as int?) ?? 0) != 0,
      read: ((r['read'] as int?) ?? 0) != 0,
      recalled: ((r['recalled'] as int?) ?? 0) != 0,
    );
  }

  void saveMessages(String convId, List<Message> messages) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM lan_messages WHERE conv_id = ?', [convId]);
      final stmt = _db.prepare('''
        INSERT INTO lan_messages
          (id, conv_id, sender_id, sender_name, kind, text, file_name,
           file_size, file_mime, file_url, file_token, file_path, file_width,
           file_height, sent_at, edited_at, status, delivered, read, recalled)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(conv_id, id) DO UPDATE SET
          sender_name = excluded.sender_name,
          text = excluded.text,
          file_path = excluded.file_path,
          status = excluded.status,
          delivered = excluded.delivered,
          read = excluded.read,
          recalled = excluded.recalled
      ''');
      for (final m in messages) {
        stmt.execute([
          m.id,
          convId,
          m.senderId,
          m.senderName,
          m.kind.name,
          m.text,
          m.file?.name,
          m.file?.size ?? 0,
          m.file?.mime,
          m.file?.url,
          m.file?.token,
          m.file?.path,
          m.file?.width ?? 0,
          m.file?.height ?? 0,
          m.sentAt.millisecondsSinceEpoch,
          m.editedAt?.millisecondsSinceEpoch,
          m.status,
          m.delivered ? 1 : 0,
          m.read ? 1 : 0,
          m.recalled ? 1 : 0,
        ]);
      }
      stmt.close();
      _db.execute('COMMIT');
    } catch (_) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  String? loadMeta(String key) {
    final rows = _db.select('SELECT value FROM lan_meta WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    return '${rows.first['value']}';
  }

  void saveMeta(String key, String value) {
    _db.execute(
      'INSERT INTO lan_meta (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  void deleteMeta(String key) {
    _db.execute('DELETE FROM lan_meta WHERE key = ?', [key]);
  }
}
