import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'frame.dart';
import 'protocol_helpers.dart';

const discoveryPort = 42223;
const discoveryGroup = '239.255.77.77';
const announceHello = 'hello';
const announceProbe = 'probe';
const announceBye = 'bye';

class Announcement {
  final String app;
  final int v;
  final String kind;
  final String id;
  final String instance;
  final String name;
  final String signature;
  final String status;
  final String version;
  final String platform;
  final int port;
  final int transferPort;
  final int ts;

  Announcement({
    this.app = 'zchat',
    this.v = protoVersion,
    required this.kind,
    required this.id,
    this.instance = '',
    this.name = '',
    this.signature = '',
    this.status = 'online',
    this.version = '',
    this.platform = '',
    required this.port,
    this.transferPort = 0,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
    'app': app,
    'v': v,
    'kind': kind,
    'id': id,
    if (instance.isNotEmpty) 'instance': instance,
    'name': name,
    if (signature.isNotEmpty) 'signature': signature,
    'status': status,
    if (version.isNotEmpty) 'version': version,
    if (platform.isNotEmpty) 'platform': platform,
    'port': port,
    if (transferPort != 0) 'transferPort': transferPort,
    'ts': ts,
  };

  List<int> encode() => utf8.encode(jsonEncode(toJson()));
}

class Discovery {
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  int _port = discoveryPort;
  bool _active = false;
  String selfId = '';
  void Function(Announcement ann, String ip)? onAnnouncement;
  void Function(String message)? onError;

  bool get active => _active;

  Future<void> start({
    required int port,
    required String selfId,
    required bool enabled,
  }) async {
    await stop();
    this.selfId = selfId;
    if (!enabled) return;
    _port = port == 0 ? discoveryPort : port;
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: true,
      );
    } catch (_) {
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _port,
          reuseAddress: true,
        );
      } catch (_) {
        try {
          socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
            reuseAddress: true,
          );
          onError?.call('UDP $_port 已被占用，自动发现仅能发送');
        } catch (e) {
          onError?.call('UDP 启动失败：$e');
          return;
        }
      }
    }
    _socket = socket;
    socket.broadcastEnabled = true;
    socket.multicastLoopback = true;
    try {
      socket.multicastHops = 1;
    } catch (_) {}
    final group = InternetAddress(discoveryGroup);
    try {
      socket.joinMulticast(group);
    } catch (_) {}
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        try {
          socket.joinMulticast(group, iface);
        } catch (_) {}
      }
    } catch (_) {}
    _sub = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        while (true) {
          final dg = socket!.receive();
          if (dg == null) break;
          _handleDatagram(dg);
        }
      },
      onError: (Object e) {
        onError?.call('UDP 错误：$e');
      },
    );
    _active = true;
  }

  void _handleDatagram(Datagram dg) {
    if (dg.data.length > 65536) return;
    try {
      final raw = jsonDecode(utf8.decode(dg.data));
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      if (m['app']?.toString() != 'zchat') return;
      if (asInt(m['v']) != protoVersion) return;
      final id = asString(m['id']);
      if (id.isEmpty || id == selfId) return;
      final port = asInt(m['port']);
      if (port <= 0 || port > 65535) return;
      final ann = Announcement(
        kind: asString(m['kind'], announceHello),
        id: id,
        instance: asString(m['instance']),
        name: asString(m['name']),
        signature: asString(m['signature']),
        status: asString(m['status'], 'online'),
        version: asString(m['version']),
        platform: asString(m['platform']),
        port: port,
        transferPort: asInt(m['transferPort']),
        ts: asInt(m['ts']),
      );
      onAnnouncement?.call(ann, dg.address.address);
    } catch (_) {}
  }

  Future<void> sendAnnouncement(Announcement ann) async {
    final socket = _socket;
    if (socket == null) return;
    final bytes = ann.encode();
    final group = InternetAddress(discoveryGroup);
    try {
      socket.send(bytes, group, _port);
    } catch (_) {
      onError?.call('发送 UDP 组播失败');
    }
    try {
      socket.send(bytes, InternetAddress('255.255.255.255'), _port);
    } catch (_) {}
    try {
      final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final seen = <String>{};
      for (final iface in list) {
        for (final addr in iface.addresses) {
          final bcast = broadcastFor(addr);
          if (bcast == null) continue;
          if (!seen.add(bcast)) continue;
          try {
            socket.send(bytes, InternetAddress(bcast), _port);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    _active = false;
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> release() => stop();

  static String? broadcastFor(InternetAddress a) {
    final raw = a.rawAddress;
    if (raw.length != 4) return null;
    const prefix = 24;
    var ip = 0;
    for (final b in raw) {
      ip = (ip << 8) | (b & 0xff);
    }
    final host = (1 << (32 - prefix)) - 1;
    final bcast = ip | host;
    return '${(bcast >> 24) & 0xff}.${(bcast >> 16) & 0xff}.'
        '${(bcast >> 8) & 0xff}.${bcast & 0xff}';
  }

  static String? primaryIp(List<String> addresses) {
    for (final a in addresses) {
      if (!a.startsWith('127.') && !a.startsWith('169.254.')) return a;
    }
    return addresses.isEmpty ? null : addresses.first;
  }

  static String platformLabel() {
    final os = Platform.operatingSystem;
    var arch = '';
    try {
      arch = Abi.current().toString().split('.').last;
    } catch (_) {}
    return arch.isEmpty ? os : '$os/$arch';
  }
}
