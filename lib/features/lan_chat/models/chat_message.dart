/// 消息类型
enum MessageType { text, file, system }

/// 发送状态
enum SendStatus { sending, sent, failed }

/// 文件传输方向
enum TransferDirection { send, receive }

/// 文件传输状态
enum TransferStatus { pending, transferring, done, failed, cancelled }

/// 聊天消息
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final MessageType type;
  final String content;
  final DateTime timestamp;
  final bool isMe;
  bool isRead;
  SendStatus sendStatus;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.type,
    required this.content,
    required this.timestamp,
    this.isMe = false,
    this.isRead = false,
    this.sendStatus = SendStatus.sent,
  });

  /// 从 TCP JSON 协议解析远程消息
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      type: _parseType(json['type'] as String? ?? 'text'),
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  static MessageType _parseType(String t) {
    switch (t) {
      case 'file':
        return MessageType.file;
      case 'system':
        return MessageType.system;
      default:
        return MessageType.text;
    }
  }

  ChatMessage copyWith({bool? isRead, bool? isMe, SendStatus? sendStatus}) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      type: type,
      content: content,
      timestamp: timestamp,
      isMe: isMe ?? this.isMe,
      isRead: isRead ?? this.isRead,
      sendStatus: sendStatus ?? this.sendStatus,
    );
  }
}

/// 文件传输信息（嵌在 ChatMessage.content 的 JSON 中）
class FileTransferInfo {
  final String fileName;
  final int fileSize;
  final String? filePath; // 本地完整路径
  final TransferDirection direction;
  final TransferStatus status;
  final double progress;
  final String? errorMessage;

  FileTransferInfo({
    required this.fileName,
    required this.fileSize,
    this.filePath,
    this.direction = TransferDirection.send,
    this.status = TransferStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
  });

  String get sizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'type': 'file_meta',
        'fileName': fileName,
        'fileSize': fileSize,
      };

  factory FileTransferInfo.fromJson(Map<String, dynamic> json) {
    return FileTransferInfo(
      fileName: json['fileName'] as String? ?? '',
      fileSize: json['fileSize'] as int? ?? 0,
    );
  }

  FileTransferInfo copyWith({
    String? fileName,
    int? fileSize,
    String? filePath,
    TransferDirection? direction,
    TransferStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    return FileTransferInfo(
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      filePath: filePath ?? this.filePath,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}