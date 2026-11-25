import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../models/lan_models.dart';
import '../models/peer.dart';
import '../protocol/frame.dart';
import '../protocol/image_utils.dart';
import '../protocol/peer_node.dart';
import '../protocol/protocol_helpers.dart';
import '../protocol/share_server.dart';
import '../protocol/transfer_client.dart';
import '../protocol/transfer_server.dart';
import '../repositories/lan_store.dart';
import '../services/lan_settings.dart';

const _identityMetaKey = 'identity';
const _outboxMetaKey = 'outbox';

class LanChatController extends ChangeNotifier {
  LanSettings settings = LanSettings();
  late Profile profile;
  late AppLocalizations l10n;
  late LanStore store;

  TransferServer? transfer;
  ShareServer? share;
  PeerNode? node;

  final Map<String, Peer> peers = {};
  final Map<String, Conversation> convs = {};
  final Map<String, List<Message>> msgs = {};
  Map<String, List<Frame>> outbox = {};

  final Map<String, DownloadState> downloads = {};
  final Map<String, SendProgress> sends = {};
  final Map<String, String> sendTokenMap = {};
  final Map<String, TypingState> typing = {};
  final Map<String, DateTime> lastRead = {};

  final ValueNotifier<String?> toastNotifier = ValueNotifier(null);

  String activeConvId = '';
  bool appVisible = true;
  bool ready = false;
  bool shareExplicit = false;
  String version = '1.0.0';
  List<String> localIps = [];

  Timer? _stateTimer;
  Timer? _toastTimer;
  Timer? _saveTimer;
  final Map<String, Timer> _typingTimers = {};
  bool _disposed = false;
  bool _startingTransfer = false;
  bool _shuttingDown = false;
  DateTime? _lastTypingAt;

  final String selfId;
  String selfName;

  LanChatController({required this.selfId, required String selfName})
    : selfName = selfName.isEmpty ? 'Zebra' : selfName {
    profile = Profile(id: selfId, name: this.selfName);
  }

  bool get running => ready;

  Future<void> init() async {
    await LanPaths.init();
    settings = await LanSettings.load();
    l10n = AppLocalizations(
      Locale(settings.language.toLowerCase().startsWith('zh') ? 'zh' : 'en'),
    );
    store = LanStore();
    profile = _loadProfile();

    for (final c in store.loadConversations()) {
      convs[c.id] = c;
      msgs[c.id] = [];
    }
    for (final c in convs.values.toList()) {
      final list = store.loadMessages(c.id);
      for (final m in list) {
        m.mine = m.senderId == profile.id;
      }
      msgs[c.id] = list;
      if (list.isNotEmpty) c.last = list.last;
    }
    _loadOutbox();

    transfer = TransferServer(LanPaths.tcpTransfersFile);
    await transfer!.loadRegistry();
    transfer!.onProgress = _onTransferProgress;
    transfer!.onError = _setToast;
    try {
      await transfer!.start(settings.transferPort);
      settings.transferPort = transfer!.port;
    } catch (e) {
      _setToast(e.toString());
    }

    share = ShareServer(LanPaths.httpTransfersFile);
    await share!.loadTransfers();
    share!.onProgress = _onShareProgress;
    share!.onError = _setToast;
    share!.english = settings.language.startsWith('en');
    share!.dir = await _validDir(settings.shareDir);
    share!.uploadDir = await _validDir(settings.uploadDir);

    localIps = await _localIps();
    await _startNode();

    if (settings.shareOnStart &&
        (settings.shareDir.isNotEmpty || settings.uploadDir.isNotEmpty)) {
      await startShare(announce: false, quiet: true);
    }

    rebuildSendTokens();
    if (activeConvId.isEmpty) {
      final ordered = orderedConversations();
      if (ordered.isNotEmpty) activeConvId = ordered.first.id;
    }

    ready = true;
    await _saveSettings();
    _scheduleStateSave();
    _bump();
  }

  Profile _loadProfile() {
    final raw = store.loadMeta(_identityMetaKey);
    if (raw != null) {
      try {
        final obj = jsonDecode(raw);
        if (obj is Map) {
          final m = Map<String, dynamic>.from(obj);
          final id = asString(m['id']);
          if (id.isNotEmpty) {
            return Profile(
              id: id,
              name: asString(m['name'], selfName),
              signature: asString(m['signature']),
              status: presenceFrom(m['status']),
            );
          }
        }
      } catch (_) {}
    }
    return Profile(id: selfId, name: selfName, status: Presence.online);
  }

  void _loadOutbox() {
    final raw = store.loadMeta(_outboxMetaKey);
    if (raw == null) return;
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) return;
      outbox = {};
      obj.forEach((key, value) {
        if (value is! List) return;
        final list = <Frame>[];
        for (final item in value) {
          if (item is Map) {
            try {
              list.add(Frame.fromJson(Map<String, dynamic>.from(item)));
            } catch (_) {}
          }
        }
        if (list.isNotEmpty) outbox['$key'] = list;
      });
    } catch (_) {}
  }

  Future<void> _startNode() async {
    final tp = (transfer != null && transfer!.running) ? transfer!.port : 0;
    final n = PeerNode(
      profile: profile,
      version: version,
      port: settings.port,
      transferPort: tp,
      discoveryEnabled: settings.discovery,
      discoveryPortValue: settings.discoveryPort,
    );
    n.onPeer = _applyPeer;
    n.onConnect = (peer) {
      _applyPeer(peer);
      flushOutbox(peer.id);
    };
    n.onDisconnect = (id) {
      final peer = peers[id];
      if (peer != null) {
        peer.connected = false;
        _scheduleStateSave();
        _bump();
      }
    };
    n.onFrame = _handleFrame;
    n.onError = (message) {
      _setToast(message);
      _bump();
    };
    node = n;
    try {
      await n.start();
      localIps = await _localIps();
      settings.port = n.port;
    } catch (e) {
      _setToast(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  int get port => node?.port ?? settings.port;
  int get transferPort => transfer?.port ?? settings.transferPort;
  int get sharePort => share?.port ?? settings.sharePort;
  bool get discoveryActive => node?.discoveryActive ?? false;
  bool get shareRunning => share?.running ?? false;

  Future<int> startServer() async {
    if (!ready) await init();
    return port;
  }

  @override
  void dispose() {
    _disposed = true;
    _stateTimer?.cancel();
    _toastTimer?.cancel();
    _saveTimer?.cancel();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    toastNotifier.dispose();
    super.dispose();
  }

  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    await _flushState();
    await node?.stop();
    node = null;
    await share?.stop();
    await transfer?.stop();
  }

  Future<void> _flushState() async {
    _stateTimer?.cancel();
    _stateTimer = null;
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveConversations();
    for (final id in msgs.keys.toList()) {
      try {
        store.saveMessages(id, msgs[id] ?? const []);
      } catch (_) {}
    }
    _saveOutbox();
  }

  Future<List<String>> _localIps() async {
    final out = <String>[];
    try {
      final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in list) {
        for (final a in iface.addresses) {
          if (!a.isLoopback) out.add(a.address);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<String> _validDir(String path) async {
    if (path.isEmpty) return '';
    try {
      final stat = await Directory(path).stat();
      if (stat.type == FileSystemEntityType.directory) return path;
    } catch (_) {}
    return '';
  }

  void _bump() {
    if (!_disposed) notifyListeners();
  }

  void _setToast(String message) {
    if (_disposed) return;
    final text = message.trim();
    if (text.isEmpty) return;
    toastNotifier.value = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (toastNotifier.value == text) toastNotifier.value = null;
    });
  }

  // -- persistence ------------------------------------------------------

  void _scheduleStateSave() {
    if (_disposed || _shuttingDown) return;
    if (_stateTimer?.isActive ?? false) return;
    _stateTimer = Timer(const Duration(milliseconds: 300), () {
      _stateTimer = null;
      _saveConversations();
      _saveOutbox();
    });
  }

  Future<void> _saveConversations() async {
    try {
      store.saveMeta(
        _identityMetaKey,
        jsonEncode({
          'id': profile.id,
          'name': profile.name,
          'signature': profile.signature,
          'status': presenceValue(profile.status),
        }),
      );
      for (final c in convs.values) {
        store.saveConversation(c);
      }
    } catch (_) {}
  }

  void _saveOutbox() {
    try {
      final data = <String, dynamic>{};
      outbox.forEach((key, value) {
        if (value.isNotEmpty) {
          data[key] = value.map((f) => f.toJson()).toList();
        }
      });
      if (data.isEmpty) {
        store.deleteMeta(_outboxMetaKey);
      } else {
        store.saveMeta(_outboxMetaKey, jsonEncode(data));
      }
    } catch (_) {}
  }

  void _scheduleMessageSave(String convId) {
    if (_disposed || _shuttingDown) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _saveTimer = null;
      try {
        store.saveMessages(convId, msgs[convId] ?? const []);
      } catch (_) {}
    });
    _scheduleStateSave();
  }

  Future<void> _saveSettings() async {
    try {
      settings.language = l10n.locale.languageCode;
      await settings.save();
    } catch (_) {}
  }

  Future<void> setLanguage(String languageCode) async {
    l10n = AppLocalizations(Locale(languageCode == 'zh' ? 'zh' : 'en'));
    if (share != null) share!.english = languageCode == 'en';
    await _saveSettings();
    _bump();
  }

  // -- peers / conversations --------------------------------------------

  void _applyPeer(Peer incoming) {
    final existing = peers[incoming.id];
    final merged = Peer(
      id: incoming.id,
      name: incoming.name.isEmpty && existing != null
          ? existing.name
          : incoming.name,
      signature: incoming.signature,
      avatar: incoming.avatar.isEmpty && existing != null
          ? existing.avatar
          : incoming.avatar,
      status: incoming.status,
      ip: incoming.ip.isEmpty && existing != null ? existing.ip : incoming.ip,
      port: incoming.port == 0 && existing != null
          ? existing.port
          : incoming.port,
      transferPort: incoming.transferPort == 0 && existing != null
          ? existing.transferPort
          : incoming.transferPort,
      version: incoming.version,
      platform: incoming.platform,
      lastSeen: incoming.lastSeen ?? DateTime.now(),
      connected: incoming.connected,
      alias: existing?.alias ?? '',
      manual: existing?.manual ?? false,
    );
    peers[merged.id] = merged;
    node?.rememberPeer(merged);
    _scheduleStateSave();
    _bump();
  }

  Peer peer(String id) => peers[id] ?? Peer(id: id);

  String peerName(String id) {
    if (id == profile.id) return profile.name;
    final peer = peers[id];
    if (peer != null) return peer.displayName;
    return l10n.translate('unknownDevice');
  }

  String conversationTitle(Conversation c) {
    if (c.kind == ConvKind.group) {
      return c.title.isEmpty ? l10n.translate('groupChat') : c.title;
    }
    final peer = peers[c.peerId];
    return peer?.displayName ??
        (c.title.isEmpty ? l10n.translate('unknownDevice') : c.title);
  }

  Conversation? conversation(String id) => convs[id];

  List<Conversation> orderedConversations() {
    final list = convs.values.toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      if (byTime != 0) return byTime;
      return conversationTitle(
        a,
      ).toLowerCase().compareTo(conversationTitle(b).toLowerCase());
    });
    return list;
  }

  List<Peer> sortedPeers() {
    final list = peers.values.toList();
    list.sort((a, b) {
      if (a.connected != b.connected) return a.connected ? -1 : 1;
      final aa = presenceAvailable(a.status);
      final bb = presenceAvailable(b.status);
      if (aa != bb) return aa ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  int get totalUnread =>
      convs.values.where((c) => !c.muted).fold(0, (sum, c) => sum + c.unread);

  Conversation ensureDirect(Peer peer) {
    var c = convs[peer.id];
    if (c != null && c.kind == ConvKind.direct) return c;
    c = Conversation(
      id: peer.id,
      kind: ConvKind.direct,
      peerId: peer.id,
      title: peer.displayName,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    convs[c.id] = c;
    msgs.putIfAbsent(c.id, () => []);
    peers[peer.id] = peer;
    store.saveConversation(c);
    _scheduleStateSave();
    return c;
  }

  Conversation ensurePeerConversation(String peerId) {
    final existing = convs[peerId];
    if (existing != null) return existing;
    return ensureDirect(peer(peerId));
  }

  void openConversation(String id) {
    if (!convs.containsKey(id)) return;
    if (activeConvId.isNotEmpty && activeConvId != id) {
      stopTyping(activeConvId);
    }
    activeConvId = id;
    final c = convs[id]!;
    c.unread = 0;
    store.saveConversation(c);
    _markActiveRead();
    queueActiveImages();
    _scheduleStateSave();
    _bump();
  }

  void leaveConversation() {
    if (activeConvId.isNotEmpty) stopTyping(activeConvId);
    activeConvId = '';
    _bump();
  }

  void setAppVisible(bool visible) {
    appVisible = visible;
    if (visible) {
      _markActiveRead();
      queueActiveImages();
    }
    _bump();
  }

  bool get activeVisible => appVisible && activeConvId.isNotEmpty;

  void _markActiveRead() {
    final c = convs[activeConvId];
    if (c == null) return;
    if (c.unread != 0) {
      c.unread = 0;
      store.saveConversation(c);
      _bump();
    }
    if (c.kind != ConvKind.direct) return;
    final last = lastRead[c.id];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 1)) {
      return;
    }
    final list = msgs[c.id] ?? const <Message>[];
    DateTime? at;
    for (var i = list.length - 1; i >= 0; i--) {
      if (!list[i].mine) {
        at = list[i].sentAt;
        break;
      }
    }
    if (at == null) return;
    lastRead[c.id] = DateTime.now();
    sendFrame(
      c.peerId,
      newFrame(profile.id, typeRead, {
        'convId': c.id,
        'time': at.millisecondsSinceEpoch,
      }),
    );
  }

  // -- incoming ---------------------------------------------------------

  void _handleFrame(String peerId, Frame f) {
    final data = f.dataMap;
    if (data == null) return;
    try {
      switch (f.type) {
        case typeChat:
          final raw = data['message'];
          if (raw is Map) {
            receiveMessage(
              peerId,
              Message.fromJson(Map<String, dynamic>.from(raw)),
            );
          }
          break;
        case typeAck:
          receiveAck(asString(data['messageId']));
          break;
        case typeRead:
          receiveRead(peerId, data);
          break;
        case typeTyping:
          receiveTyping(peerId, data);
          break;
        case typeRecall:
          receiveRecall(peerId, asString(data['messageId']));
          break;
        case typeGroup:
          receiveGroup(peerId, data);
          break;
      }
    } catch (_) {}
  }

  bool _hasMessage(String convId, String messageId) {
    for (final m in msgs[convId] ?? const <Message>[]) {
      if (m.id == messageId) return true;
    }
    return false;
  }

  void receiveMessage(String from, Message m) {
    m.mine = false;
    if (m.senderId.isEmpty) m.senderId = from;
    if (m.id.isEmpty) m.id = newId('m');
    from = m.senderId;
    var peer = peers[from];
    if (peer == null) {
      final known = node?.peer(from);
      if (known != null) {
        peer = known;
        peers[from] = peer;
      } else {
        peer = Peer(
          id: from,
          name: m.senderName,
          status: Presence.online,
          connected: true,
          lastSeen: DateTime.now(),
        );
        peers[from] = peer;
      }
    }
    if (m.file != null) m.file!.path = '';
    var c = convs[m.convId];
    if (m.convId.startsWith('g_')) {
      if (c == null || c.kind != ConvKind.group) return;
    } else if (c == null || c.kind != ConvKind.direct) {
      c = ensureDirect(peer);
      m.convId = c.id;
    }
    if (m.senderName.isEmpty) m.senderName = peerName(m.senderId);
    if (m.kind != MessageKind.system) m.delivered = true;

    if (_hasMessage(c.id, m.id)) {
      sendFrame(
        from,
        newFrame(profile.id, typeAck, {
          'messageId': m.id,
          'time': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      return;
    }

    msgs.putIfAbsent(c.id, () => []).add(m);
    c.updatedAt = m.sentAt;
    c.last = m;
    _scheduleMessageSave(c.id);

    sendFrame(
      from,
      newFrame(profile.id, typeAck, {
        'messageId': m.id,
        'time': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    if (activeConvId == c.id && activeVisible) {
      _markActiveRead();
    } else if (!c.muted) {
      c.unread++;
    }
    if (m.kind == MessageKind.image && settings.autoDownloadImages) {
      autoDownloadImage(c.id, m.id);
    }
    _bump();
  }

  void receiveAck(String messageId) {
    if (messageId.isEmpty) return;
    for (final entry in msgs.entries) {
      for (final m in entry.value) {
        if (m.id != messageId) continue;
        m.delivered = true;
        if (m.status != 'read') m.status = 'delivered';
        _scheduleMessageSave(entry.key);
        _bump();
        return;
      }
    }
  }

  void receiveRead(String from, Map<String, dynamic> data) {
    var convId = asString(data['convId']);
    if (!convId.startsWith('g_') && convs.containsKey(from)) convId = from;
    final list = msgs[convId];
    if (list == null || list.isEmpty) return;
    final time = asInt(data['time']);
    if (time <= 0) return;
    final at = DateTime.fromMillisecondsSinceEpoch(time);
    var changed = false;
    for (final m in list) {
      if (m.mine && !m.sentAt.isAfter(at) && !m.read) {
        m.read = true;
        m.delivered = true;
        m.status = 'read';
        changed = true;
      }
    }
    if (changed) {
      _scheduleMessageSave(convId);
      if (activeConvId == convId) _bump();
    }
  }

  void receiveTyping(String from, Map<String, dynamic> data) {
    var convId = asString(data['convId']);
    if (!convId.startsWith('g_')) convId = from;
    final key = '$convId\x00$from';
    final on = asBool(data['on']);
    if (!on) {
      typing.remove(key);
      _typingTimers.remove(key)?.cancel();
      if (activeConvId == convId) _bump();
      return;
    }
    typing[key] = TypingState(convId, from, DateTime.now());
    _typingTimers.remove(key)?.cancel();
    _typingTimers[key] = Timer(const Duration(seconds: 4), () {
      _typingTimers.remove(key);
      final st = typing[key];
      if (st != null &&
          DateTime.now().difference(st.updatedAt) >=
              const Duration(seconds: 3)) {
        typing.remove(key);
        if (activeConvId == convId) _bump();
      }
    });
    if (activeConvId == convId) _bump();
  }

  List<String> typingNames(Conversation c) {
    final out = <String>[];
    for (final st in typing.values) {
      if (st.convId != c.id || st.peerId == profile.id) continue;
      out.add(peerName(st.peerId));
    }
    return out;
  }

  void receiveRecall(String from, String messageId) {
    if (messageId.isEmpty) return;
    for (final entry in msgs.entries) {
      for (final m in entry.value) {
        if (m.id != messageId) continue;
        if (m.senderId != from && m.senderId != profile.id) return;
        m.recalled = true;
        forgetMessageFiles([m]);
        _scheduleMessageSave(entry.key);
        _bump();
        return;
      }
    }
  }

  // -- outgoing ---------------------------------------------------------

  Future<void> sendText(String text) async {
    final c = convs[activeConvId];
    if (c == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    addLocalMessage(
      c,
      Message(
        id: newId('m'),
        convId: c.id,
        senderId: profile.id,
        senderName: profile.name,
        kind: MessageKind.text,
        text: trimmed,
        sentAt: DateTime.now(),
        status: 'sent',
        mine: true,
      ),
    );
    c.draft = '';
    sendTyping(false);
  }

  void addLocalMessage(Conversation c, Message m) {
    m.mine = true;
    m.convId = c.id;
    if (m.senderName.isEmpty) m.senderName = profile.name;
    msgs.putIfAbsent(c.id, () => []).add(m);
    c.updatedAt = m.sentAt;
    c.draft = '';
    c.last = m;
    _scheduleMessageSave(c.id);
    dispatchMessage(c, m);
    if (activeConvId == c.id) _markActiveRead();
    _bump();
  }

  void dispatchMessage(Conversation c, Message m) {
    final f = newFrame(profile.id, typeChat, {'message': m.wireJson()});
    if (c.kind == ConvKind.group) {
      for (final id in c.members) {
        if (id != profile.id) deliver(id, f);
      }
    } else if (c.peerId.isNotEmpty) {
      deliver(c.peerId, f);
    }
  }

  void deliver(String peerId, Frame f) {
    if (peerId.isEmpty || peerId == profile.id) return;
    final n = node;
    if (n != null && n.send(peerId, f)) return;
    final list = outbox.putIfAbsent(peerId, () => []);
    if (list.length >= 300) list.removeAt(0);
    list.add(f);
    _scheduleStateSave();
  }

  void sendFrame(String peerId, Frame f) {
    if (peerId.isEmpty || peerId == profile.id) return;
    node?.send(peerId, f);
  }

  void flushOutbox(String peerId) {
    final n = node;
    if (n == null) return;
    final list = outbox[peerId];
    if (list == null || list.isEmpty) return;
    final rest = <Frame>[];
    for (final f in list) {
      if (!n.send(peerId, f)) rest.add(f);
    }
    if (rest.isEmpty) {
      outbox.remove(peerId);
    } else {
      outbox[peerId] = rest;
    }
    _scheduleStateSave();
  }

  void sendTyping(bool on) {
    final c = convs[activeConvId];
    if (c == null) return;
    if (on) {
      final now = DateTime.now();
      final last = _lastTypingAt;
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        return;
      }
      _lastTypingAt = now;
    }
    final f = newFrame(profile.id, typeTyping, {'convId': c.id, 'on': on});
    if (c.kind == ConvKind.group) {
      for (final id in c.members) {
        if (id != profile.id) sendFrame(id, f);
      }
    } else {
      sendFrame(c.peerId, f);
    }
  }

  void stopTyping(String convId) {
    final c = convs[convId];
    if (c == null) return;
    final f = newFrame(profile.id, typeTyping, {'convId': c.id, 'on': false});
    if (c.kind == ConvKind.group) {
      for (final id in c.members) {
        if (id != profile.id) sendFrame(id, f);
      }
    } else {
      sendFrame(c.peerId, f);
    }
  }

  void setDraft(String convId, String text) {
    final c = convs[convId];
    if (c == null || c.draft == text) return;
    c.draft = text;
    _scheduleStateSave();
  }

  // -- message actions --------------------------------------------------

  Message? message(String convId, String messageId) {
    for (final m in msgs[convId] ?? const <Message>[]) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  List<Message> messagesOf(String convId) => msgs[convId] ?? const [];

  void recallMessage(String convId, String messageId) {
    final c = convs[convId];
    if (c == null) return;
    for (final m in msgs[convId] ?? const <Message>[]) {
      if (m.id != messageId || !m.mine) continue;
      if (DateTime.now().difference(m.sentAt) > const Duration(minutes: 2)) {
        _setToast(l10n.translate('recallExpired'));
        return;
      }
      m.recalled = true;
      forgetMessageFiles([m]);
      _scheduleMessageSave(convId);
      final f = newFrame(profile.id, typeRecall, {'messageId': messageId});
      if (c.kind == ConvKind.group) {
        for (final id in c.members) {
          if (id != profile.id) deliver(id, f);
        }
      } else {
        deliver(c.peerId, f);
      }
      _bump();
      return;
    }
  }

  void deleteMessage(String convId, String messageId) {
    final list = msgs[convId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    forgetMessageFiles([list[idx]]);
    list.removeAt(idx);
    final c = convs[convId];
    if (c != null) c.last = list.isEmpty ? null : list.last;
    store.deleteMessage(convId, messageId);
    _scheduleStateSave();
    _bump();
  }

  void deleteMessages(String convId, List<String> ids) {
    final list = msgs[convId];
    if (list == null || ids.isEmpty) return;
    final set = ids.toSet();
    final removed = list.where((m) => set.contains(m.id)).toList();
    forgetMessageFiles(removed);
    list.removeWhere((m) => set.contains(m.id));
    final c = convs[convId];
    if (c != null) c.last = list.isEmpty ? null : list.last;
    store.deleteMessages(convId, ids);
    _scheduleStateSave();
    _bump();
  }

  void clearHistory(String convId) {
    if (!msgs.containsKey(convId)) return;
    forgetMessageFiles(msgs[convId] ?? const []);
    msgs[convId] = [];
    final c = convs[convId];
    if (c != null) {
      c.last = null;
      c.unread = 0;
      store.saveConversation(c);
    }
    try {
      store.saveMessages(convId, const []);
    } catch (_) {}
    _bump();
  }

  void deleteConversation(String convId) {
    final c = convs[convId];
    if (c == null) return;
    if (c.kind == ConvKind.group) {
      leaveGroup(c);
      return;
    }
    forgetMessageFiles(msgs[convId] ?? const []);
    convs.remove(convId);
    msgs.remove(convId);
    if (activeConvId == convId) activeConvId = '';
    store.deleteConversation(convId);
    _scheduleStateSave();
    _bump();
  }

  void togglePinned(String convId) {
    final c = convs[convId];
    if (c == null) return;
    c.pinned = !c.pinned;
    store.saveConversation(c);
    _bump();
  }

  void toggleMuted(String convId) {
    final c = convs[convId];
    if (c == null) return;
    c.muted = !c.muted;
    store.saveConversation(c);
    _bump();
  }

  // -- groups -----------------------------------------------------------

  Conversation createGroup(String name, List<String> picked) {
    var title = name.trim();
    if (title.isEmpty) title = l10n.translate('unnamedGroup');
    final members = <String>[profile.id];
    final seen = <String>{profile.id};
    for (final id in picked) {
      if (id.isEmpty || !seen.add(id)) continue;
      members.add(id);
    }
    final now = DateTime.now();
    final g = Group(
      id: newId('g'),
      name: title,
      owner: profile.id,
      members: members,
      createdAt: now,
      updatedAt: now,
    );
    final c = g.conversation()..updatedAt = now;
    convs[c.id] = c;
    msgs[c.id] = [];
    store.saveConversation(c);
    appendSystem(
      c,
      '${l10n.translate('youCreatedGroup')}$title${l10n.translate('quoteEnd')}',
    );
    sendGroupAction(g, groupInvite, '');
    _scheduleStateSave();
    openConversation(c.id);
    return c;
  }

  Group groupForConv(Conversation c) => Group(
    id: c.id,
    name: conversationTitle(c),
    owner: c.owner,
    members: List<String>.from(c.members),
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
  );

  void sendGroupAction(Group g, String action, String intro) {
    final f = newFrame(profile.id, typeGroup, {
      'action': action,
      'group': g.toJson(),
      if (intro.isNotEmpty) 'intro': intro,
    });
    for (final id in g.members) {
      if (id != profile.id) deliver(id, f);
    }
  }

  void receiveGroup(String from, Map<String, dynamic> data) {
    final raw = data['group'];
    if (raw is! Map) return;
    final g = Group.fromJson(Map<String, dynamic>.from(raw));
    if (g.id.isEmpty || !g.id.startsWith('g_')) return;
    final action = asString(data['action']);
    final intro = asString(data['intro']);
    switch (action) {
      case groupInvite:
        receiveInvite(from, g, intro);
        break;
      case groupUpdate:
        receiveGroupUpdate(from, g);
        break;
      case groupLeave:
        receiveGroupLeave(g, from);
        break;
      case groupDisband:
        final c = convs[g.id];
        if (c != null) {
          final title = c.title;
          forgetMessageFiles(msgs[g.id] ?? const []);
          convs.remove(g.id);
          msgs.remove(g.id);
          if (activeConvId == g.id) activeConvId = '';
          store.deleteConversation(g.id);
          _scheduleStateSave();
          _setToast('${l10n.translate('groupDisbanded')}$title');
          _bump();
        }
        break;
    }
  }

  void receiveInvite(String from, Group g, String intro) {
    if (!g.hasMember(profile.id)) return;
    final existing = convs[g.id];
    if (existing != null) {
      applyGroup(existing, g);
      store.saveConversation(existing);
      _bump();
      return;
    }
    final c = g.conversation();
    if (c.title.isEmpty) c.title = l10n.translate('groupChat');
    c.updatedAt = DateTime.now();
    convs[c.id] = c;
    msgs[c.id] = [];
    store.saveConversation(c);
    var text = '${peerName(from)} ${l10n.translate('invitedYou')}';
    if (intro.isNotEmpty) text += '${l10n.translate('colon')}$intro';
    appendSystem(c, text);
    c.unread = 1;
    _scheduleStateSave();
    _setToast('$text ${c.title}');
    _bump();
  }

  void receiveGroupUpdate(String from, Group g) {
    var c = convs[g.id];
    if (c == null) {
      if (!g.hasMember(profile.id)) return;
      c = g.conversation();
      convs[g.id] = c;
      msgs[g.id] = [];
      store.saveConversation(c);
      appendSystem(
        c,
        '${l10n.translate('youJoinedGroup')}${conversationTitle(c)}${l10n.translate('quoteEnd')}',
      );
    } else {
      if (!g.hasMember(profile.id)) {
        final title = c.title;
        forgetMessageFiles(msgs[g.id] ?? const []);
        convs.remove(g.id);
        msgs.remove(g.id);
        if (activeConvId == g.id) activeConvId = '';
        store.deleteConversation(g.id);
        _setToast('${l10n.translate('youWereRemoved')}$title');
        _scheduleStateSave();
        _bump();
        return;
      }
      applyGroup(c, g);
      store.saveConversation(c);
    }
    _scheduleStateSave();
    _bump();
  }

  void receiveGroupLeave(Group g, String from) {
    final c = convs[g.id];
    if (c == null) return;
    final before = c.members.length;
    c.members.remove(from);
    if (c.members.length == before) return;
    c.updatedAt = DateTime.now();
    appendSystem(c, '${peerName(from)} ${l10n.translate('leftGroup')}');
    store.saveConversation(c);
    _bump();
  }

  void applyGroup(Conversation c, Group g) {
    c.title = g.name;
    c.owner = g.owner;
    c.members = List<String>.from(g.members);
    c.updatedAt = DateTime.now();
  }

  void renameGroup(String convId, String name) {
    final c = convs[convId];
    final title = name.trim();
    if (c == null || title.isEmpty || title == c.title) return;
    c.title = title;
    c.updatedAt = DateTime.now();
    appendSystem(c, '${l10n.translate('renamedGroup')}$title');
    sendGroupAction(groupForConv(c), groupUpdate, '');
    store.saveConversation(c);
    _bump();
  }

  void addGroupMembers(String convId, List<String> ids) {
    final c = convs[convId];
    if (c == null) return;
    final seen = c.members.toSet();
    var added = 0;
    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) continue;
      c.members.add(id);
      added++;
    }
    if (added == 0) return;
    c.updatedAt = DateTime.now();
    appendSystem(c, '${l10n.translate('addedMembers')}$added');
    sendGroupAction(groupForConv(c), groupUpdate, '');
    store.saveConversation(c);
    _bump();
  }

  void removeGroupMember(String convId, String id) {
    final c = convs[convId];
    if (c == null || id == profile.id) return;
    c.members.remove(id);
    c.updatedAt = DateTime.now();
    appendSystem(c, '${peerName(id)} ${l10n.translate('removedMember')}');
    sendGroupAction(groupForConv(c), groupUpdate, '');
    store.saveConversation(c);
    _bump();
  }

  void leaveGroup(Conversation c) {
    final g = groupForConv(c);
    final f = newFrame(profile.id, typeGroup, {
      'action': groupLeave,
      'group': g.toJson(),
    });
    for (final id in c.members) {
      if (id != profile.id) deliver(id, f);
    }
    forgetMessageFiles(msgs[c.id] ?? const []);
    convs.remove(c.id);
    msgs.remove(c.id);
    if (activeConvId == c.id) activeConvId = '';
    store.deleteConversation(c.id);
    _scheduleStateSave();
    _setToast('${l10n.translate('leftGroupToast')}${c.title}');
    _bump();
  }

  void disbandGroup(Conversation c) {
    final g = groupForConv(c);
    final f = newFrame(profile.id, typeGroup, {
      'action': groupDisband,
      'group': g.toJson(),
    });
    for (final id in c.members) {
      if (id != profile.id) deliver(id, f);
    }
    forgetMessageFiles(msgs[c.id] ?? const []);
    convs.remove(c.id);
    msgs.remove(c.id);
    if (activeConvId == c.id) activeConvId = '';
    store.deleteConversation(c.id);
    _scheduleStateSave();
    _setToast('${l10n.translate('groupDisbanded')}${c.title}');
    _bump();
  }

  void appendSystem(Conversation c, String text) {
    final m = Message(
      id: newId('m'),
      convId: c.id,
      senderId: profile.id,
      senderName: profile.name,
      kind: MessageKind.system,
      text: text,
      sentAt: DateTime.now(),
    );
    msgs.putIfAbsent(c.id, () => []).add(m);
    c.updatedAt = m.sentAt;
    c.last = m;
    _scheduleMessageSave(c.id);
  }

  List<Peer> groupMembers(Conversation c) {
    final out = <Peer>[];
    for (final id in c.members) {
      if (id == profile.id) {
        out.add(profile.asPeer('', 0, 0));
        continue;
      }
      final peer = peers[id];
      out.add(
        peer ??
            Peer(
              id: id,
              name: l10n.translate('unknownMember'),
              status: Presence.offline,
            ),
      );
    }
    return out;
  }

  // -- files ------------------------------------------------------------

  Future<bool> ensureTransfer() async {
    if (transfer != null && transfer!.running) return true;
    if (_startingTransfer) {
      while (_startingTransfer) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return transfer != null && transfer!.running;
    }
    _startingTransfer = true;
    try {
      transfer ??= TransferServer(LanPaths.tcpTransfersFile);
      transfer!.onProgress = _onTransferProgress;
      transfer!.onError = _setToast;
      await transfer!.loadRegistry();
      await transfer!.start(settings.transferPort);
      settings.transferPort = transfer!.port;
      node?.setTransferPort(transfer!.port);
      return transfer!.running;
    } catch (_) {
      return false;
    } finally {
      _startingTransfer = false;
    }
  }

  Future<bool> ensureShareServer() async {
    final s = share;
    if (s == null) return false;
    if (s.running) return true;
    s.dir = await _validDir(settings.shareDir);
    s.uploadDir = '';
    shareExplicit = false;
    try {
      await s.start(settings.sharePort);
      settings.sharePort = s.port;
      return true;
    } catch (e) {
      _setToast('${l10n.translate('shareStartFailed')}$e');
      return false;
    }
  }

  Future<void> startShare({bool announce = true, bool quiet = false}) async {
    final s = share;
    if (s == null) return;
    final shareDir = await _validDir(settings.shareDir);
    final uploadDir = await _validDir(settings.uploadDir);
    if (settings.shareDir.isNotEmpty && shareDir.isEmpty) {
      _setToast(l10n.translate('shareDirMissing'));
      return;
    }
    if (settings.uploadDir.isNotEmpty && uploadDir.isEmpty) {
      _setToast(l10n.translate('uploadDirMissing'));
      return;
    }
    s.dir = shareDir;
    s.uploadDir = uploadDir;
    try {
      await s.start(settings.sharePort);
      settings.sharePort = s.port;
    } catch (e) {
      shareExplicit = false;
      _setToast('${l10n.translate('shareStartFailed')}$e');
      return;
    }
    shareExplicit = true;
    if (announce) {
      settings.shareOnStart = true;
      await _saveSettings();
      if (!quiet) _setToast(l10n.translate('shareStarted'));
    }
    _bump();
  }

  Future<void> stopShare() async {
    await share?.stop();
    share?.uploadDir = '';
    shareExplicit = false;
    settings.shareOnStart = false;
    await _saveSettings();
    _bump();
  }

  List<String> shareUrls() {
    final s = share;
    if (s == null || !s.running) return [];
    return s.urls(localIps);
  }

  String shareUrl() {
    final urls = shareUrls();
    return urls.isEmpty ? '' : urls.first;
  }

  Future<int> sendFiles(List<String> files) async {
    final c = convs[activeConvId];
    if (c == null) {
      _setToast(l10n.translate('openChatFirst'));
      return 0;
    }
    if (files.isEmpty) return 0;
    final tcpReady = await ensureTransfer();
    final httpReady = await ensureShareServer();
    if (!tcpReady && !httpReady) {
      _setToast(l10n.translate('transferUnavailable'));
      return 0;
    }
    var added = 0;
    for (final path in files) {
      try {
        final stat = await File(path).stat();
        if (stat.type != FileSystemEntityType.file) continue;
      } catch (_) {
        continue;
      }
      FileMeta? file;
      if (tcpReady) {
        try {
          final tr = await transfer!.add(path);
          file = FileMeta(
            name: tr.name,
            size: tr.size,
            mime: tr.mime,
            token: tr.token,
            path: path,
          );
        } catch (_) {}
      }
      if (httpReady) {
        try {
          final st = await share!.addTransfer(path);
          if (file == null) {
            file = FileMeta(
              name: st.name,
              size: st.size,
              mime: st.mime,
              path: path,
            );
          } else {
            file.url = share!.transferUrl(
              share!.primaryHost(localIps),
              st,
              localIps,
            );
          }
        } catch (_) {}
      }
      if (file == null) continue;
      var kind = MessageKind.file;
      if (file.mime.toLowerCase().startsWith('image/')) {
        kind = MessageKind.image;
        try {
          final bytes = await File(path).readAsBytes();
          final dims = await imageDimensions(bytes);
          if (dims != null) {
            file.width = dims.$1;
            file.height = dims.$2;
          }
        } catch (_) {}
      }
      final m = Message(
        id: newId('m'),
        convId: c.id,
        senderId: profile.id,
        senderName: profile.name,
        kind: kind,
        file: file,
        sentAt: DateTime.now(),
        status: 'sent',
        mine: true,
      );
      if (file.token.isNotEmpty) sendTokenMap[file.token] = m.id;
      final shareToken = shareTokenFromUrl(file.url);
      if (shareToken != null) sendTokenMap[shareToken] = m.id;
      sends[m.id] = SendProgress(total: file.size);
      addLocalMessage(c, m);
      added++;
    }
    if (added == 0) _setToast(l10n.translate('noSendableFiles'));
    return added;
  }

  void _onTransferProgress(String token, int sent, int total, String? error) {
    _applySendProgress(token, 'TCP', sent, total, error);
  }

  void _onShareProgress(String token, int sent, int total, String? error) {
    _applySendProgress(token, 'HTTP', sent, total, error);
  }

  void _applySendProgress(
    String token,
    String transport,
    int sent,
    int total,
    String? error,
  ) {
    final msgId = sendTokenMap[token];
    if (msgId == null) return;
    final st = sends.putIfAbsent(msgId, () => SendProgress());
    final now = DateTime.now();
    if (error != null) {
      st.sent = sent;
      st.total = total;
      st.error = _transferErrorText(error);
      st.working = false;
      st.done = false;
      st.speed = 0;
      st.transport = transport;
      st.lastAt = DateTime.fromMillisecondsSinceEpoch(0);
      st.lastSent = sent;
      _bump();
      return;
    }
    final resumed =
        st.error.isNotEmpty || (st.lastSent > 0 && sent < st.lastSent);
    if (st.lastAt.millisecondsSinceEpoch == 0 || resumed) {
      st.lastAt = now;
      st.lastSent = sent;
      st.speed = 0;
    } else if (sent > st.lastSent) {
      var dt = now.difference(st.lastAt).inMicroseconds / 1e6;
      if (dt < 0.001) dt = 0.001;
      final inst = (sent - st.lastSent) / dt;
      st.speed = st.speed == 0 ? inst : st.speed * 0.7 + inst * 0.3;
      st.lastAt = now;
      st.lastSent = sent;
    }
    st.sent = sent;
    st.total = total;
    st.error = '';
    st.transport = transport;
    st.working = total > 0 && sent < total;
    st.done = sent >= total;
    if (st.done) {
      st.working = false;
      st.speed = 0;
    }
    _bump();
  }

  void rebuildSendTokens() {
    sendTokenMap.clear();
    for (final list in msgs.values) {
      for (final m in list) {
        if (!m.mine || m.file == null) continue;
        if (m.file!.token.isNotEmpty) sendTokenMap[m.file!.token] = m.id;
        final tok = shareTokenFromUrl(m.file!.url);
        if (tok != null) sendTokenMap[tok] = m.id;
      }
    }
  }

  String _transferErrorText(String codeOrMessage) {
    const keys = {
      'bad_request': 'errBadRequest',
      'not_found': 'errNotFound',
      'file_missing': 'errFileMissing',
      'bad_offset': 'errBadOffset',
      'file_changed': 'errFileChanged',
      'io_error': 'errIo',
      'checksum_mismatch': 'errIncomplete',
      'too_large': 'errTooLarge',
      'busy': 'errBusy',
    };
    final key = keys[codeOrMessage];
    return key == null ? codeOrMessage : l10n.translate(key);
  }

  void _downloadError(String convId, String msgId, String message) {
    final st =
        downloads[msgId] ?? DownloadState(convId: convId, messageId: msgId);
    st.working = false;
    st.error = message;
    st.updatedAt = DateTime.now();
    downloads[msgId] = st;
    _bump();
  }

  void _downloadProgress(String convId, String msgId, int done, int total) {
    final st =
        downloads[msgId] ?? DownloadState(convId: convId, messageId: msgId);
    st.working = true;
    st.error = '';
    st.total = total;
    st.value = total > 0 ? (done / total).clamp(0.0, 1.0) : 0;
    st.updatedAt = DateTime.now();
    downloads[msgId] = st;
    _bump();
  }

  Future<void> autoDownloadImage(String convId, String msgId) async {
    final m = message(convId, msgId);
    if (m == null || m.file == null) return;
    if (m.file!.path.isNotEmpty) return;
    if (m.file!.url.isEmpty && m.file!.token.isEmpty) return;
    final ext = p.extension(sanitizeFileName(m.file!.name));
    final dest = p.join(
      LanPaths.imagesCacheDir,
      '${sha256Hex(m.id)}${ext.isEmpty ? '.img' : ext}',
    );
    await downloadTo(convId, msgId, dest, true);
  }

  void queueActiveImages() {
    if (!settings.autoDownloadImages) return;
    final c = convs[activeConvId];
    if (c == null) return;
    for (final m in msgs[c.id] ?? const <Message>[]) {
      if (m.kind == MessageKind.image &&
          m.file != null &&
          m.file!.path.isEmpty &&
          (m.file!.url.isNotEmpty || m.file!.token.isNotEmpty)) {
        autoDownloadImage(c.id, m.id);
      }
    }
  }

  Future<String?> downloadMessage(String convId, String msgId) async {
    final m = message(convId, msgId);
    if (m == null || m.file == null) return null;
    if (m.file!.path.isNotEmpty && await File(m.file!.path).exists()) {
      return m.file!.path;
    }
    final name = sanitizeFileName(
      m.file!.name.isEmpty ? l10n.translate('fileDefaultName') : m.file!.name,
    );
    final dest = await uniquePath(settings.downloadDir, name);
    final ok = await downloadTo(convId, msgId, dest, false);
    return ok ? m.file?.path : null;
  }

  Future<bool> downloadTo(
    String convId,
    String msgId,
    String dest,
    bool imageOnly,
  ) async {
    final m = message(convId, msgId);
    if (m == null || m.file == null) return false;
    final existing = downloads[msgId];
    if (existing != null && existing.working) return false;
    final file = m.file!;
    final st = DownloadState(
      convId: convId,
      messageId: msgId,
      total: file.size,
      working: true,
    );
    downloads[msgId] = st;
    _bump();
    final peer = peers[m.senderId];
    final addr = peer?.transferAddr ?? '';
    if (file.token.isNotEmpty && addr.isNotEmpty) {
      final ok = await _downloadSocket(convId, msgId, m, addr, dest, imageOnly);
      if (ok) return true;
    }
    if (file.url.isNotEmpty) {
      return _downloadHttp(convId, msgId, m, file.url, dest, imageOnly);
    }
    _downloadError(convId, msgId, l10n.translate('downloadUnavailable'));
    return false;
  }

  String _partPath(String msgId) =>
      p.join(LanPaths.transfersCacheDir, '${sha256Hex(msgId)}.part');

  Future<bool> _downloadSocket(
    String convId,
    String msgId,
    Message m,
    String addr,
    String dest,
    bool imageOnly,
  ) async {
    final fallback = m.file!.url;
    final part = _partPath(msgId);
    RandomAccessFile? raf;
    try {
      await Directory(p.dirname(part)).create(recursive: true);
      var offset = 0;
      final partFile = File(part);
      if (await partFile.exists()) offset = await partFile.length();
      final want = m.file!.size;
      if (want > 0 && offset > want) {
        await partFile.delete();
        offset = 0;
      }
      if (want > 0 && offset == want) {
        return await _completeTransfer(
          convId,
          msgId,
          part,
          dest,
          offset,
          imageOnly,
        );
      }
      raf = await partFile.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      final result = await TransferClient.download(
        addr: addr,
        token: m.file!.token,
        offset: offset,
        onData: (chunk) async {
          await raf!.writeFrom(chunk);
        },
        onProgress: (done, total) {
          _downloadProgress(convId, msgId, done, total);
        },
      );
      await raf.flush();
      await raf.close();
      raf = null;
      return await _completeTransfer(
        convId,
        msgId,
        part,
        dest,
        result.done,
        imageOnly,
      );
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      if (fallback.isNotEmpty) {
        try {
          final uri = Uri.parse(fallback);
          final host = peer(m.senderId).ip;
          final url = host.isEmpty
              ? fallback
              : uri.replace(host: host).toString();
          return await _downloadHttp(convId, msgId, m, url, dest, imageOnly);
        } catch (_) {}
      }
      _downloadError(convId, msgId, _downloadErrorText(e));
      return false;
    }
  }

  Future<bool> _downloadHttp(
    String convId,
    String msgId,
    Message m,
    String url,
    String dest,
    bool imageOnly,
  ) async {
    final want = m.file!.size;
    final part = '$dest.part';
    HttpClient? client;
    RandomAccessFile? raf;
    try {
      await Directory(p.dirname(part)).create(recursive: true);
      var offset = 0;
      final partFile = File(part);
      if (await partFile.exists()) offset = await partFile.length();
      if (want > 0 && offset > want) {
        await partFile.delete();
        offset = 0;
      }
      if (want > 0 && offset == want) {
        return await _completeTransfer(
          convId,
          msgId,
          part,
          dest,
          offset,
          imageOnly,
        );
      }
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(url));
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close();
      if (response.statusCode == HttpStatus.partialContent) {
        // resumed
      } else if (response.statusCode == HttpStatus.ok) {
        offset = 0;
        try {
          await partFile.delete();
        } catch (_) {}
      } else if (response.statusCode ==
          HttpStatus.requestedRangeNotSatisfiable) {
        if (want > 0 && offset == want) {
          return await _completeTransfer(
            convId,
            msgId,
            part,
            dest,
            offset,
            imageOnly,
          );
        }
        throw StateError('HTTP ${response.statusCode}');
      } else {
        throw StateError('HTTP ${response.statusCode}');
      }
      var total = want;
      if (total <= 0 && response.contentLength > 0) {
        total = offset + response.contentLength;
      }
      final st =
          downloads[msgId] ?? DownloadState(convId: convId, messageId: msgId);
      st.total = total;
      st.working = true;
      st.error = '';
      st.transport = 'HTTP';
      st.value = total > 0 ? offset / total : 0;
      downloads[msgId] = st;
      _bump();
      raf = await partFile.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      var done = offset;
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in response) {
        await raf.writeFrom(chunk);
        done += chunk.length;
        final now = DateTime.now();
        if (now.difference(last) >= const Duration(milliseconds: 150) ||
            (total > 0 && done >= total)) {
          last = now;
          _downloadProgress(convId, msgId, done, total);
        }
      }
      await raf.flush();
      await raf.close();
      raf = null;
      if (want > 0 && done != want) {
        try {
          await partFile.delete();
        } catch (_) {}
        throw StateError(l10n.translate('sizeMismatch'));
      }
      return await _completeTransfer(
        convId,
        msgId,
        part,
        dest,
        done,
        imageOnly,
      );
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      _downloadError(convId, msgId, _downloadErrorText(e));
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  String _downloadErrorText(Object error) {
    if (error is TransferError) {
      return _transferErrorText(
        error.code.isEmpty ? error.message : error.code,
      );
    }
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.contains('HTTP 404') || text.contains('HTTP 410')) {
      return l10n.translate('errFileExpired');
    }
    if (text.contains('connection closed') ||
        text.contains('Connection reset') ||
        text.contains('Broken pipe')) {
      return l10n.translate('errDisconnected');
    }
    return text;
  }

  Future<bool> _completeTransfer(
    String convId,
    String msgId,
    String part,
    String dest,
    int done,
    bool imageOnly,
  ) async {
    try {
      final finalPath = await uniquePath(p.dirname(dest), p.basename(dest));
      await Directory(p.dirname(finalPath)).create(recursive: true);
      await moveFile(part, finalPath);
      final m = message(convId, msgId);
      if (m != null && m.file != null) m.file!.path = finalPath;
      downloads.remove(msgId);
      _scheduleMessageSave(convId);
      if (!imageOnly) _setToast('${l10n.translate('savedTo')}$finalPath');
      _bump();
      return true;
    } catch (e) {
      _downloadError(convId, msgId, e.toString());
      return false;
    }
  }

  void forgetMessageFiles(List<Message> messages) {
    final tcpTokens = <String>[];
    for (final m in messages) {
      final f = m.file;
      if (f == null) continue;
      sends.remove(m.id);
      downloads.remove(m.id);
      if (f.token.isNotEmpty) {
        tcpTokens.add(f.token);
        sendTokenMap.remove(f.token);
      }
      final tok = shareTokenFromUrl(f.url);
      if (tok != null) {
        sendTokenMap.remove(tok);
        share?.removeTransfer(tok);
      }
    }
    if (tcpTokens.isNotEmpty) transfer?.removeMany(tcpTokens);
  }

  // -- profile / settings / network -------------------------------------

  Future<void> updateProfile({String? name, String? signature}) async {
    if (name != null && name.trim().isNotEmpty) {
      profile.name = name.trim();
      selfName = profile.name;
    }
    if (signature != null) profile.signature = signature;
    node?.setProfile(profile);
    await _saveConversations();
    _bump();
  }

  Future<void> setStatus(Presence status) async {
    profile.status = status;
    node?.setStatus(status);
    await _saveConversations();
    _bump();
  }

  Future<void> setDiscovery(bool enabled) async {
    settings.discovery = enabled;
    await restartNetwork();
  }

  Future<void> setSettings(void Function(LanSettings s) mutate) async {
    mutate(settings);
    await _saveSettings();
    _bump();
  }

  Future<void> restartNetwork() async {
    final n = node;
    node = null;
    await n?.stop();
    if (transfer != null && transfer!.running) {
      await transfer!.stop();
      try {
        await transfer!.start(settings.transferPort);
        settings.transferPort = transfer!.port;
      } catch (e) {
        _setToast(e.toString());
      }
    }
    await _startNode();
    for (final peer in peers.values) {
      peer.connected = false;
    }
    await _saveSettings();
    _bump();
  }

  Future<Peer> manualConnect(String addr) async {
    final n = node;
    if (n == null) throw StateError('network not ready');
    final peer = await n.connectAddress(addr);
    _applyPeer(peer);
    flushOutbox(peer.id);
    return peer;
  }

  Future<Peer> connectPeer(String peerId) async {
    final peer = peers[peerId];
    if (peer == null) throw StateError('unknown peer');
    if (peer.connected) return peer;
    if (peer.ip.isEmpty) throw StateError('no address');
    final n = node;
    if (n == null) throw StateError('network not ready');
    final p = await n.connectAddress(peer.addr);
    _applyPeer(p);
    return p;
  }

  void setAlias(String peerId, String alias) {
    final peer = peers[peerId];
    if (peer == null) return;
    peer.alias = alias.trim();
    node?.rememberPeer(peer);
    _scheduleStateSave();
    _bump();
  }

  void removePeer(String peerId) {
    if (peerId == profile.id) return;
    final conv = convs[peerId];
    if (conv != null && conv.kind == ConvKind.direct) {
      forgetMessageFiles(msgs[peerId] ?? const []);
      convs.remove(peerId);
      msgs.remove(peerId);
      if (activeConvId == peerId) activeConvId = '';
      store.deleteConversation(peerId);
    }
    peers.remove(peerId);
    _scheduleStateSave();
    _bump();
  }

  Map<String, dynamic>? shareTokenForMessage(Message m) {
    if (m.file == null) return null;
    final s = share;
    final tok = shareTokenFromUrl(m.file!.url);
    if (s == null || tok == null) return null;
    final tr = s.transferFor(tok);
    if (tr == null) return null;
    return {
      'name': tr.name,
      'size': tr.size,
      'mime': tr.mime,
      'url': m.file!.url,
    };
  }

  static int progressPercent(int sent, int total) =>
      total <= 0 ? 0 : (sent * 100 ~/ total).clamp(0, 100);
}
