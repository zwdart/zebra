import 'chat_message.dart';

/// 房间消息:复用 ChatMessage,附加 roomId 标识所属房间。
/// 帧类型为 'room_msg',房间内 v1 仅文本+系统消息。
class RoomChatMessage extends ChatMessage {
  final String roomId;

  RoomChatMessage({
    required this.roomId,
    required super.id,
    required super.senderId,
    required super.senderName,
    required super.type,
    required super.content,
    required super.timestamp,
    super.isMe,
    super.isRead,
    super.sendStatus,
  });

  /// 从 TCP 'room_msg' 帧 JSON 解析(帧 type 字段为 'room_msg')
  factory RoomChatMessage.fromJson(Map<String, dynamic> json) {
    return RoomChatMessage(
      roomId: json['roomId'] as String? ?? '',
      id: json['msgId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      type: _parseType(json['messageType'] as String? ?? 'text'),
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// 发送用帧 JSON(帧类型固定 'room_msg',消息类型放 messageType 字段,
  /// 与单聊帧的 type=text/system 区分,避免消息类型与帧类型混淆)
  Map<String, dynamic> toRoomJson() => {
        'type': 'room_msg',
        'roomId': roomId,
        'msgId': id,
        'senderId': senderId,
        'senderName': senderName,
        'messageType': type.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  static MessageType _parseType(String t) {
    switch (t) {
      case 'system':
        return MessageType.system;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }
}
