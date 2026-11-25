import 'dart:convert';

const protoVersion = 1;
const maxFrame = 2 << 20;

const typeHello = 'hello';
const typePresence = 'presence';
const typeBye = 'bye';
const typePing = 'ping';
const typePong = 'pong';
const typeChat = 'chat';
const typeAck = 'ack';
const typeRead = 'read';
const typeTyping = 'typing';
const typeRecall = 'recall';
const typeGroup = 'group';

const groupInvite = 'invite';
const groupUpdate = 'update';
const groupLeave = 'leave';
const groupDisband = 'disband';

class Frame {
  final int v;
  final String type;
  final String from;
  final String to;
  final String id;
  final int time;
  final Object? data;

  Frame({
    this.v = protoVersion,
    required this.type,
    required this.from,
    this.to = '',
    this.id = '',
    this.time = 0,
    this.data,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'v': v, 'type': type, 'from': from};
    if (to.isNotEmpty) m['to'] = to;
    if (id.isNotEmpty) m['id'] = id;
    if (time != 0) m['time'] = time;
    if (data != null) m['data'] = data;
    return m;
  }

  String encodeLine() => '${jsonEncode(toJson())}\n';

  factory Frame.fromJson(Map<String, dynamic> m) {
    final v = (m['v'] as num?)?.toInt() ?? 0;
    if (v != protoVersion) throw FormatException('unsupported version $v');
    final type = m['type']?.toString() ?? '';
    if (type.isEmpty) throw const FormatException('frame has no type');
    return Frame(
      v: v,
      type: type,
      from: m['from']?.toString() ?? '',
      to: m['to']?.toString() ?? '',
      id: m['id']?.toString() ?? '',
      time: (m['time'] as num?)?.toInt() ?? 0,
      data: m['data'],
    );
  }

  factory Frame.decode(String line) {
    final raw = jsonDecode(line);
    if (raw is! Map) throw const FormatException('frame is not an object');
    return Frame.fromJson(Map<String, dynamic>.from(raw));
  }

  Map<String, dynamic>? get dataMap {
    if (data is Map) return Map<String, dynamic>.from(data as Map);
    return null;
  }
}

Frame newFrame(String from, String type, [Object? data]) =>
    Frame(v: protoVersion, type: type, from: from, data: data);
