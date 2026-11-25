import '../protocol/protocol_helpers.dart';

enum Presence { online, away, busy, dnd, invisible, offline }

const presenceOptions = [
  Presence.online,
  Presence.away,
  Presence.busy,
  Presence.dnd,
  Presence.invisible,
];

Presence presenceFrom(Object? value) {
  switch (value?.toString()) {
    case 'away':
      return Presence.away;
    case 'busy':
      return Presence.busy;
    case 'dnd':
      return Presence.dnd;
    case 'invisible':
      return Presence.invisible;
    case 'offline':
      return Presence.offline;
    default:
      return Presence.online;
  }
}

String presenceValue(Presence p) => p.name;

bool presenceAvailable(Presence p) =>
    p != Presence.offline && p != Presence.invisible;

class Peer {
  String id;
  String name;
  String signature;
  String avatar;
  Presence status;
  String ip;
  int port;
  int transferPort;
  String version;
  String platform;
  DateTime? lastSeen;
  bool connected;
  String alias;
  bool manual;

  Peer({
    required this.id,
    this.name = '',
    this.signature = '',
    this.avatar = '',
    this.status = Presence.offline,
    this.ip = '',
    this.port = 0,
    this.transferPort = 0,
    this.version = '',
    this.platform = '',
    this.lastSeen,
    this.connected = false,
    this.alias = '',
    this.manual = false,
  });

  String get displayName {
    if (alias.trim().isNotEmpty) return alias;
    if (name.trim().isNotEmpty) return name;
    if (ip.isNotEmpty) return ip;
    return id;
  }

  String get addr => port == 0 ? ip : '$ip:$port';
  String get transferAddr =>
      (ip.isEmpty || transferPort == 0) ? '' : '$ip:$transferPort';

  bool get available => connected && presenceAvailable(status) && ip.isNotEmpty;

  Map<String, dynamic> toJson({bool runtime = false}) {
    final m = <String, dynamic>{
      'id': id,
      'name': name,
      'status': presenceValue(status),
      'lastSeen': lastSeen == null
          ? rfc3339(DateTime.now())
          : rfc3339(lastSeen!),
    };
    if (signature.isNotEmpty) m['signature'] = signature;
    if (avatar.isNotEmpty) m['avatar'] = avatar;
    if (ip.isNotEmpty) m['ip'] = ip;
    if (port != 0) m['port'] = port;
    if (transferPort != 0) m['transferPort'] = transferPort;
    if (version.isNotEmpty) m['version'] = version;
    if (platform.isNotEmpty) m['platform'] = platform;
    if (alias.isNotEmpty) m['alias'] = alias;
    if (manual) m['manual'] = true;
    if (runtime) m['connected'] = connected;
    return m;
  }

  factory Peer.fromJson(Map<String, dynamic> m) {
    return Peer(
      id: asString(m['id']),
      name: asString(m['name']),
      signature: asString(m['signature']),
      avatar: asString(m['avatar']),
      status: presenceFrom(m['status']),
      ip: asString(m['ip']),
      port: asInt(m['port']),
      transferPort: asInt(m['transferPort']),
      version: asString(m['version']),
      platform: asString(m['platform']),
      lastSeen: parseTime(m['lastSeen']),
      connected: asBool(m['connected']),
      alias: asString(m['alias']),
      manual: asBool(m['manual']),
    );
  }

  Peer clone() => Peer.fromJson(toJson(runtime: true));
}

class Profile {
  String id;
  String name;
  String signature;
  String avatar;
  Presence status;

  Profile({
    required this.id,
    this.name = '',
    this.signature = '',
    this.avatar = '',
    this.status = Presence.online,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (signature.isNotEmpty) 'signature': signature,
    if (avatar.isNotEmpty) 'avatar': avatar,
    'status': presenceValue(status),
  };

  factory Profile.fromJson(Map<String, dynamic> m) => Profile(
    id: asString(m['id']),
    name: asString(m['name']),
    signature: asString(m['signature']),
    avatar: asString(m['avatar']),
    status: presenceFrom(m['status']),
  );

  Peer asPeer(String ip, int port, int transferPort) => Peer(
    id: id,
    name: name,
    signature: signature,
    avatar: avatar,
    status: status,
    ip: ip,
    port: port,
    transferPort: transferPort,
    lastSeen: DateTime.now(),
    connected: true,
  );
}
