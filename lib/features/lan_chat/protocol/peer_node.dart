// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/peer.dart';
import 'discovery.dart';
import 'frame.dart';
import 'protocol_helpers.dart';
import 'socket_reader.dart';

const defaultChatPort = 42224;
const announceEvery = Duration(seconds: 4);
const peerTimeout = Duration(seconds: 16);
const dialEvery = Duration(seconds: 5);
const dialTimeout = Duration(seconds: 3);
const handshakeTimeout = Duration(seconds: 8);
const writeTimeout = Duration(seconds: 15);
const peerQueueSize = 64;

class _PeerState {
  Peer peer;
  DateTime seenAt;
  DateTime? dialedAt;
  bool dialing;
  String instance;

  _PeerState(this.peer)
    : seenAt = DateTime.now(),
      dialing = false,
      instance = '';
}

class PeerNode {
  final Discovery discovery = Discovery();
  final Map<String, _PeerState> _peers = {};
  final Map<String, _PeerConn> _conns = {};

  Profile _profile;
  int _port = 0;
  int _transferPort = 0;
  int _discoveryPort = discoveryPort;
  String version;
  bool _discoveryEnabled = true;
  bool _started = false;
  bool _stopped = false;
  ServerSocket? _server;
  StreamSubscription<Socket>? _acceptSub;
  Timer? _loop;
  DateTime _lastAnnounce = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDial = DateTime.fromMillisecondsSinceEpoch(0);
  final String instance = newId('boot');

  void Function(Peer peer)? onPeer;
  void Function(Peer peer)? onConnect;
  void Function(String peerId)? onDisconnect;
  void Function(String peerId, Frame frame)? onFrame;
  void Function(String message)? onError;

  PeerNode({
    required Profile profile,
    required this.version,
    int port = defaultChatPort,
    int transferPort = 0,
    bool discoveryEnabled = true,
    int discoveryPortValue = discoveryPort,
  }) : _profile = profile,
       _port = port,
       _transferPort = transferPort,
       _discoveryEnabled = discoveryEnabled,
       _discoveryPort = discoveryPortValue;

  Profile get profile => _profile;
  int get port => _port;
  int get transferPort => _transferPort;
  bool get started => _started;
  bool get discoveryActive => discovery.active;

  List<Peer> get peers =>
      _peers.values.map((e) => e.peer).toList(growable: false);

  Peer? peer(String id) => _peers[id]?.peer;

  bool connected(String id) => _conns.containsKey(id) && !_conns[id]!.closed;

  Future<void> start() async {
    if (_started) return;
    _stopped = false;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
    } catch (e) {
      throw StateError('无法监听 TCP 端口 $_port：$e');
    }
    _port = _server!.port;
    _acceptSub = _server!.listen(
      _accept,
      onError: (Object e) {
        _report('TCP 接受连接失败：$e');
      },
    );
    discovery.selfId = _profile.id;
    discovery.onAnnouncement = _onAnnouncement;
    discovery.onError = _report;
    await discovery.start(
      port: _discoveryPort,
      selfId: _profile.id,
      enabled: _discoveryEnabled,
    );
    _started = true;
    _loop = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    announceNow();
  }

  Future<void> stop() async {
    if (!_started && _server == null) return;
    _stopped = true;
    _started = false;
    _loop?.cancel();
    _loop = null;
    await _sendByeAndClose();
    final server = _server;
    _server = null;
    await _acceptSub?.cancel();
    _acceptSub = null;
    try {
      await server?.close();
    } catch (_) {}
    await discovery.release();
    _conns.clear();
    for (final ps in _peers.values) {
      ps.peer.connected = false;
    }
  }

  Future<void> _sendByeAndClose() async {
    if (discovery.active) {
      await _announce(announceBye, status: 'offline');
    }
    final bye = newFrame(_profile.id, typeBye, {'reason': 'quit'});
    final line = bye.encodeLine();
    for (final c in _conns.values.toList()) {
      try {
        c.socket.add(utf8.encode(line));
        await c.socket.flush().timeout(const Duration(milliseconds: 200));
      } catch (_) {}
      c.close();
    }
  }

  Future<void> restart({
    required Profile profile,
    required bool discoveryEnabled,
    int? port,
    int? transferPort,
    int? discoveryPortValue,
  }) async {
    await stop();
    _profile = profile;
    _discoveryEnabled = discoveryEnabled;
    _port = port ?? _port;
    _transferPort = transferPort ?? _transferPort;
    _discoveryPort = discoveryPortValue ?? _discoveryPort;
    _peers.clear();
    await start();
  }

  void setProfile(Profile p) {
    final oldId = _profile.id;
    _profile = p;
    if (oldId != p.id) _peers.remove(oldId);
    _broadcastPresence();
    announceNow();
  }

  void setStatus(Presence status) {
    _profile.status = status;
    _broadcastPresence();
    announceNow();
  }

  void setTransferPort(int port) {
    _transferPort = port;
    announceNow();
  }

  void updateLocalProfile({String? name, String? signature, String? avatar}) {
    if (name != null) _profile.name = name;
    if (signature != null) _profile.signature = signature;
    if (avatar != null) _profile.avatar = avatar;
    announceNow();
  }

  void _broadcastPresence() {
    broadcast(
      newFrame(_profile.id, typePresence, {
        'name': _profile.name,
        if (_profile.signature.isNotEmpty) 'signature': _profile.signature,
        if (_profile.avatar.isNotEmpty) 'avatar': _profile.avatar,
        'status': presenceValue(_profile.status),
      }),
    );
  }

  void announceNow() {
    _announce(announceHello);
    if (discovery.active) _announce(announceProbe);
  }

  Future<void> _announce(String kind, {String? status}) async {
    if (!discovery.active) return;
    final s = status ?? presenceValue(_profile.status);
    await discovery.sendAnnouncement(
      Announcement(
        kind: kind,
        id: _profile.id,
        instance: instance,
        name: _profile.name,
        signature: _profile.signature,
        status: s,
        version: version,
        platform: Discovery.platformLabel(),
        port: _port,
        transferPort: _transferPort,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    if (now.difference(_lastAnnounce) >= announceEvery) {
      _lastAnnounce = now;
      await _announce(announceHello);
    }
    if (now.difference(_lastDial) >= const Duration(milliseconds: 500)) {
      _lastDial = now;
      _dialDiscovered();
    }
    _expirePeers(now);
  }

  void _onAnnouncement(Announcement a, String srcIp) {
    if (a.app != 'zchat' || a.v != protoVersion) return;
    if (a.id.isEmpty || a.id == _profile.id) return;
    if (a.port <= 0 || a.port > 65535) return;
    var status = presenceFrom(a.status);
    if (a.status.isEmpty) status = Presence.online;
    if (status == Presence.invisible) status = Presence.offline;
    final fresh = !_peers.containsKey(a.id);
    final ps = _peers.putIfAbsent(a.id, () => _PeerState(Peer(id: a.id)));
    final p = ps.peer;
    if (srcIp.isNotEmpty) p.ip = srcIp;
    p.id = a.id;
    p.name = a.name;
    p.signature = a.signature;
    p.status = status;
    p.port = a.port;
    p.transferPort = a.transferPort;
    p.version = a.version;
    p.platform = a.platform;
    p.lastSeen = DateTime.now();
    p.connected = _conns.containsKey(a.id) || p.connected;
    ps.seenAt = DateTime.now();
    ps.instance = a.instance;
    if (a.kind == announceProbe) _announce(announceHello);
    if (fresh || a.kind != announceProbe) onPeer?.call(p.clone());
  }

  void _accept(Socket socket) {
    _handleIncoming(socket);
  }

  Future<void> _handleIncoming(Socket socket) async {
    try {
      final result = await _handshake(socket, outbound: false);
      if (result == null) {
        socket.destroy();
        return;
      }
      if (result.peer.id == _profile.id) {
        socket.destroy();
        return;
      }
      _register(socket, result.reader, result.peer, false);
    } catch (_) {
      socket.destroy();
    }
  }

  Future<_Handshake?> _handshake(
    Socket socket, {
    required bool outbound,
  }) async {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = SocketReader(socket);
    final selfPeer = await _selfPeer();
    final hello = newFrame(_profile.id, typeHello, {'peer': selfPeer.toJson()});
    Future<_Handshake?> run() async {
      if (outbound) {
        socket.add(utf8.encode(hello.encodeLine()));
        await socket.flush();
      }
      final line = await reader.readLine(maxFrame);
      final f = Frame.decode(line);
      if (f.type != typeHello) {
        throw FormatException('expected hello, got ${f.type}');
      }
      final data = f.dataMap;
      if (data == null || data['peer'] is! Map) {
        throw const FormatException('hello without peer');
      }
      final p = Peer.fromJson(Map<String, dynamic>.from(data['peer'] as Map));
      if (p.id.isEmpty) throw const FormatException('hello without an id');
      if (!outbound) {
        socket.add(utf8.encode(hello.encodeLine()));
        await socket.flush();
      }
      if (p.port == 0) p.port = defaultChatPort;
      final remote = socket.remoteAddress.address;
      if (remote.isNotEmpty) p.ip = remote;
      p.lastSeen = DateTime.now();
      p.connected = true;
      if (p.port == 0) p.port = socket.remotePort;
      return _Handshake(p, reader);
    }

    try {
      return await run().timeout(handshakeTimeout);
    } on TimeoutException {
      await reader.cancel();
      rethrow;
    }
  }

  Future<Peer> _selfPeer() async {
    final ips = await localAddresses();
    final ip = Discovery.primaryIp(ips) ?? '';
    return _profile.asPeer(ip, _port, _transferPort);
  }

  void _register(Socket socket, SocketReader reader, Peer p, bool outbound) {
    if (_stopped) {
      socket.destroy();
      return;
    }
    final ps = _peers.putIfAbsent(p.id, () => _PeerState(p));
    ps.peer = _mergeLocal(p, ps.peer);
    ps.peer.connected = true;
    ps.seenAt = DateTime.now();
    final old = _conns[p.id];
    if (old != null) {
      final keepOutbound = _profile.id.compareTo(p.id) < 0;
      if (outbound != keepOutbound) {
        socket.destroy();
        return;
      }
      _conns.remove(p.id);
      old.close();
    }
    final conn = _PeerConn(this, socket, reader, p.id);
    _conns[p.id] = conn;
    conn.start();
    onConnect?.call(ps.peer.clone());
    onPeer?.call(ps.peer.clone());
  }

  Peer _mergeLocal(Peer incoming, Peer existing) {
    incoming.alias = existing.alias;
    incoming.manual = existing.manual;
    if (incoming.avatar.isEmpty) incoming.avatar = existing.avatar;
    return incoming;
  }

  void _removeConn(String id, _PeerConn conn) {
    if (_conns[id] == conn) _conns.remove(id);
    final ps = _peers[id];
    if (ps != null && !_conns.containsKey(id)) {
      ps.peer.connected = false;
    }
    onDisconnect?.call(id);
    if (ps != null) onPeer?.call(ps.peer.clone());
  }

  void _handleFrame(String id, Frame f) {
    final ps = _peers[id];
    if (ps != null) ps.seenAt = DateTime.now();
    switch (f.type) {
      case typeBye:
        _markOffline(id);
        _conns[id]?.close();
        return;
      case typePresence:
        final data = f.dataMap;
        if (data == null) return;
        if (ps != null) {
          ps.peer.name = asString(data['name'], ps.peer.name);
          ps.peer.signature = asString(data['signature']);
          ps.peer.avatar = asString(data['avatar']);
          if (data['status'] != null) {
            ps.peer.status = presenceFrom(data['status']);
          }
          ps.peer.lastSeen = DateTime.now();
        }
        if (ps != null) onPeer?.call(ps.peer.clone());
        return;
      case typePing:
        send(id, newFrame(_profile.id, typePong));
        return;
      case typePong:
        return;
    }
    onFrame?.call(id, f);
  }

  void _markOffline(String id) {
    final ps = _peers[id];
    if (ps == null) return;
    ps.peer.status = Presence.offline;
    ps.peer.connected = false;
    onPeer?.call(ps.peer.clone());
  }

  void _expirePeers(DateTime now) {
    for (final ps in _peers.values.toList()) {
      if (ps.peer.connected || ps.peer.status == Presence.offline) continue;
      if (now.difference(ps.seenAt) > peerTimeout) {
        ps.peer.status = Presence.offline;
        ps.peer.connected = false;
        onPeer?.call(ps.peer.clone());
      }
    }
  }

  void _dialDiscovered() {
    if (_stopped) return;
    final now = DateTime.now();
    final targets = <_PeerState>[];
    for (final ps in _peers.values) {
      final p = ps.peer;
      if (p.id == _profile.id || p.connected || _conns.containsKey(p.id)) {
        continue;
      }
      if (ps.dialing) continue;
      if (!presenceAvailable(p.status) || p.ip.isEmpty || p.port == 0) continue;
      if (ps.dialedAt != null && now.difference(ps.dialedAt!) < dialEvery) {
        continue;
      }
      ps.dialedAt = now;
      ps.dialing = true;
      targets.add(ps);
    }
    for (final ps in targets) {
      _dialOne(ps);
    }
  }

  Future<void> _dialOne(_PeerState ps) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        ps.peer.ip,
        ps.peer.port,
        timeout: dialTimeout,
      );
      final hs = await _handshake(socket, outbound: true);
      if (hs == null) {
        socket.destroy();
        return;
      }
      if (hs.peer.id == _profile.id) {
        socket.destroy();
        return;
      }
      _register(socket, hs.reader, hs.peer, true);
    } catch (_) {
      socket?.destroy();
    } finally {
      ps.dialing = false;
    }
  }

  Future<Peer> connectAddress(String addr) async {
    var host = addr.trim();
    var port = _port == 0 ? defaultChatPort : _port;
    if (host.contains(':')) {
      final idx = host.lastIndexOf(':');
      final portText = host.substring(idx + 1);
      final parsed = int.tryParse(portText);
      if (parsed != null && parsed > 0 && parsed < 65536) {
        port = parsed;
        host = host.substring(0, idx);
      }
    }
    if (host.isEmpty) throw const FormatException('地址为空');
    final socket = await Socket.connect(host, port, timeout: handshakeTimeout);
    final hs = await _handshake(socket, outbound: true);
    if (hs == null) {
      socket.destroy();
      throw const SocketException('握手失败');
    }
    if (hs.peer.id == _profile.id) {
      socket.destroy();
      throw StateError('不能连接自己');
    }
    _register(socket, hs.reader, hs.peer, true);
    return hs.peer;
  }

  void rememberPeer(Peer p) {
    if (p.id.isEmpty) return;
    final ps = _peers.putIfAbsent(p.id, () => _PeerState(p));
    ps.peer = _mergeLocal(p, ps.peer);
    ps.seenAt = DateTime.now();
    ps.dialedAt = null;
  }

  bool send(String id, Frame f) {
    final c = _conns[id];
    if (c == null) return false;
    return c.send(f);
  }

  void broadcast(Frame f) {
    for (final c in _conns.values.toList()) {
      c.send(f);
    }
  }

  Future<List<String>> localAddresses() async {
    final out = <String>[];
    try {
      final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final iface in list) {
        for (final a in iface.addresses) {
          if (!a.isLoopback) out.add(a.address);
        }
      }
    } catch (_) {}
    return out;
  }

  void _report(String message) {
    if (message.contains('use of closed network connection')) return;
    onError?.call(message);
  }
}

class _Handshake {
  final Peer peer;
  final SocketReader reader;
  _Handshake(this.peer, this.reader);
}

class _PeerConn {
  final PeerNode node;
  final Socket socket;
  final SocketReader reader;
  final String id;
  final List<Frame> _queue = [];
  bool _closed = false;
  bool _flushing = false;

  _PeerConn(this.node, this.socket, this.reader, this.id);

  bool get closed => _closed;

  void start() {
    _readLoop();
    _flushLoop();
  }

  bool send(Frame f) {
    if (_closed) return false;
    if (_queue.length >= peerQueueSize) {
      close();
      return false;
    }
    _queue.add(f);
    _flushLoop();
    return true;
  }

  Future<void> _flushLoop() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (!_closed && _queue.isNotEmpty) {
        final f = _queue.removeAt(0);
        final line = f.encodeLine();
        if (utf8.encode(line).length > maxFrame) {
          close();
          return;
        }
        socket.add(utf8.encode(line));
        await socket.flush().timeout(writeTimeout);
      }
    } catch (_) {
      close();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _readLoop() async {
    try {
      while (!_closed) {
        final line = await reader.readLine(maxFrame);
        final f = Frame.decode(line);
        if (_closed) return;
        node._handleFrame(id, f);
      }
    } catch (_) {
      close();
    } finally {
      node._removeConn(id, this);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _queue.clear();
    try {
      socket.destroy();
    } catch (_) {}
  }
}
