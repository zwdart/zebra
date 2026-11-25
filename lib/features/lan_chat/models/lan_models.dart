import '../protocol/protocol_helpers.dart';

enum ConvKind { direct, group }

class Conversation {
  String id;
  ConvKind kind;
  String peerId;
  String title;
  String owner;
  List<String> members;
  DateTime createdAt;
  DateTime updatedAt;
  int unread;
  bool pinned;
  bool muted;
  String draft;

  Message? last;

  Conversation({
    required this.id,
    required this.kind,
    this.peerId = '',
    this.title = '',
    this.owner = '',
    List<String>? members,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.unread = 0,
    this.pinned = false,
    this.muted = false,
    this.draft = '',
    this.last,
  }) : members = members ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isGroup => kind == ConvKind.group;

  Map<String, dynamic> toJson({bool includeRuntime = false}) => {
    'id': id,
    'kind': kind.name,
    if (peerId.isNotEmpty) 'peerId': peerId,
    if (title.isNotEmpty) 'title': title,
    if (owner.isNotEmpty) 'owner': owner,
    if (members.isNotEmpty) 'members': members,
    'createdAt': rfc3339(createdAt),
    'updatedAt': rfc3339(updatedAt),
    'unread': unread,
    if (pinned) 'pinned': true,
    if (muted) 'muted': true,
    if (draft.isNotEmpty) 'draft': draft,
    if (includeRuntime && last != null) 'last': last!.toJson(),
  };

  factory Conversation.fromJson(Map<String, dynamic> m) {
    final kind = m['kind']?.toString() == 'group'
        ? ConvKind.group
        : ConvKind.direct;
    return Conversation(
      id: asString(m['id']),
      kind: kind,
      peerId: asString(m['peerId']),
      title: asString(m['title']),
      owner: asString(m['owner']),
      members: (m['members'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: parseTime(m['createdAt']) ?? DateTime.now(),
      updatedAt: parseTime(m['updatedAt']) ?? DateTime.now(),
      unread: asInt(m['unread']),
      pinned: asBool(m['pinned']),
      muted: asBool(m['muted']),
      draft: asString(m['draft']),
      last: m['last'] is Map
          ? Message.fromJson(Map<String, dynamic>.from(m['last'] as Map))
          : null,
    );
  }
}

class Group {
  String id;
  String name;
  String owner;
  List<String> members;
  DateTime createdAt;
  DateTime updatedAt;

  Group({
    required this.id,
    required this.name,
    required this.owner,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
  });

  bool hasMember(String id) => members.contains(id);

  Conversation conversation() => Conversation(
    id: id,
    kind: ConvKind.group,
    title: name,
    owner: owner,
    members: List<String>.from(members),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'owner': owner,
    'members': members,
    'createdAt': rfc3339(createdAt),
    'updatedAt': rfc3339(updatedAt),
  };

  factory Group.fromJson(Map<String, dynamic> m) => Group(
    id: asString(m['id']),
    name: asString(m['name']),
    owner: asString(m['owner']),
    members: (m['members'] as List?)?.map((e) => e.toString()).toList() ?? [],
    createdAt: parseTime(m['createdAt']) ?? DateTime.now(),
    updatedAt: parseTime(m['updatedAt']) ?? DateTime.now(),
  );
}

class FileMeta {
  String name;
  int size;
  String mime;
  String url;
  String token;
  String path;
  int width;
  int height;

  FileMeta({
    required this.name,
    required this.size,
    this.mime = '',
    this.url = '',
    this.token = '',
    this.path = '',
    this.width = 0,
    this.height = 0,
  });

  bool get isImage => isImageMime(mime);

  Map<String, dynamic> toJson({bool includePath = false}) => {
    'name': name,
    'size': size,
    if (mime.isNotEmpty) 'mime': mime,
    if (url.isNotEmpty) 'url': url,
    if (token.isNotEmpty) 'token': token,
    if (includePath && path.isNotEmpty) 'path': path,
    if (width > 0) 'width': width,
    if (height > 0) 'height': height,
  };

  factory FileMeta.fromJson(Map<String, dynamic> m) => FileMeta(
    name: asString(m['name']),
    size: asInt(m['size']),
    mime: asString(m['mime']),
    url: asString(m['url']),
    token: asString(m['token']),
    path: asString(m['path']),
    width: asInt(m['width']),
    height: asInt(m['height']),
  );
}

enum MessageKind { text, image, file, system }

class Message {
  String id;
  String convId;
  String senderId;
  String senderName;
  MessageKind kind;
  String text;
  FileMeta? file;
  DateTime sentAt;
  DateTime? editedAt;
  String status;
  bool delivered;
  bool read;
  bool recalled;
  bool mine;

  Message({
    required this.id,
    required this.convId,
    required this.senderId,
    this.senderName = '',
    this.kind = MessageKind.text,
    this.text = '',
    this.file,
    required this.sentAt,
    this.editedAt,
    this.status = '',
    this.delivered = false,
    this.read = false,
    this.recalled = false,
    this.mine = false,
  });

  Map<String, dynamic> toJson({bool includePath = false}) {
    final m = <String, dynamic>{
      'id': id,
      'convId': convId,
      'senderId': senderId,
      if (senderName.isNotEmpty) 'senderName': senderName,
      'kind': kind.name,
      if (text.isNotEmpty) 'text': text,
      if (file != null) 'file': file!.toJson(includePath: includePath),
      'sentAt': rfc3339(sentAt),
      if (editedAt != null) 'editedAt': rfc3339(editedAt!),
      if (status.isNotEmpty) 'status': status,
      if (delivered) 'delivered': true,
      if (read) 'read': true,
      if (recalled) 'recalled': true,
    };
    return m;
  }

  Map<String, dynamic> wireJson() => toJson(includePath: false);

  factory Message.fromJson(Map<String, dynamic> m) {
    MessageKind kind;
    switch (m['kind']?.toString()) {
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
    return Message(
      id: asString(m['id']),
      convId: asString(m['convId']),
      senderId: asString(m['senderId']),
      senderName: asString(m['senderName']),
      kind: kind,
      text: asString(m['text']),
      file: m['file'] is Map
          ? FileMeta.fromJson(Map<String, dynamic>.from(m['file'] as Map))
          : null,
      sentAt: parseTime(m['sentAt']) ?? DateTime.now(),
      editedAt: parseTime(m['editedAt']),
      status: asString(m['status']),
      delivered: asBool(m['delivered']),
      read: asBool(m['read']),
      recalled: asBool(m['recalled']),
    );
  }
}

class TypingState {
  final String convId;
  final String peerId;
  final DateTime updatedAt;

  TypingState(this.convId, this.peerId, this.updatedAt);
}

class SendProgress {
  int sent;
  int total;
  double speed;
  String error;
  bool working;
  bool done;
  String transport;
  DateTime lastAt;
  int lastSent;

  SendProgress({
    this.sent = 0,
    this.total = 0,
    this.speed = 0,
    this.error = '',
    this.working = false,
    this.done = false,
    this.transport = '',
    DateTime? lastAt,
    this.lastSent = 0,
  }) : lastAt = lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  double get value => total <= 0 ? (done ? 1 : 0) : (sent / total).clamp(0, 1);
}

class DownloadState {
  final String convId;
  final String messageId;
  double value;
  int total;
  bool working;
  String error;
  String transport;
  DateTime updatedAt;

  DownloadState({
    required this.convId,
    required this.messageId,
    this.value = 0,
    this.total = 0,
    this.working = false,
    this.error = '',
    this.transport = '',
  }) : updatedAt = DateTime.now();
}
