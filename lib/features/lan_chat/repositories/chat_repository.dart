import '../../../database/database_service.dart';
import '../models/chat_message.dart';

/// 聊天记录持久化仓库
class ChatRepository {
  /// 获取与某个 peer 的聊天历史（分页，最新在前）
  List<ChatMessage> getMessages(String peerId, {int page = 1, int size = 50}) {
    final rows = DatabaseService.getChatMessages(peerId, page: page, size: size);
    return rows.map((r) => _rowToMessage(r)).toList();
  }

  /// 保存一条消息
  /// [peerName] 可选:覆盖会话列表显示名(聊天室场景传房间名,否则默认用发送者名)
  void saveMessage(ChatMessage msg, String peerId, {String? peerName}) {
    DatabaseService.insertChatMessage({
      'message_id': msg.id,
      'peer_id': peerId,
      'sender_id': msg.senderId,
      'sender_name': msg.senderName,
      'type': msg.type.name,
      'content': msg.content,
      'timestamp': msg.timestamp.toIso8601String(),
      'is_me': msg.isMe ? 1 : 0,
      'is_read': msg.isRead ? 1 : 0,
    });

    // 更新会话列表
    final preview = msg.type == MessageType.text
        ? msg.content
        : msg.type == MessageType.file
            ? '[文件]'
            : '[系统消息]';
    DatabaseService.updateChatPeerLastMessage(
      peerId,
      peerName ?? msg.senderName,
      preview,
      msg.timestamp.toIso8601String(),
    );
  }

  /// 标记已读
  void markRead(String peerId) {
    DatabaseService.markChatPeerRead(peerId);
  }

  /// 获取所有会话列表
  List<Map<String, dynamic>> getPeers() {
    return DatabaseService.getChatPeers();
  }

  /// 删除与某个 peer 的聊天记录
  void deleteMessages(String peerId) {
    DatabaseService.deleteChatMessages(peerId);
  }

  /// 删除与某个 peer 的单条/多条消息(保留会话)
  void deleteMessagesByIds(String peerId, List<String> ids) {
    DatabaseService.deleteChatMessagesByIds(peerId, ids);
  }

  ChatMessage _rowToMessage(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['message_id'] as String? ?? '',
      senderId: row['sender_id'] as String? ?? '',
      senderName: row['sender_name'] as String? ?? '',
      type: _parseType(row['type'] as String? ?? 'text'),
      content: row['content'] as String? ?? '',
      timestamp: DateTime.tryParse(row['timestamp'] as String? ?? '') ?? DateTime.now(),
      isMe: (row['is_me'] as int?) == 1,
      isRead: (row['is_read'] as int?) == 1,
    );
  }

  MessageType _parseType(String t) {
    switch (t) {
      case 'file':
        return MessageType.file;
      case 'system':
        return MessageType.system;
      default:
        return MessageType.text;
    }
  }
}