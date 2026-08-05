import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';

/// 帧类型标记
const int kJsonMarker = 0x4A; // 'J'
const int kFileMarker = 0x46; // 'F'

/// TCP 消息接收回调
typedef OnMessageReceived = void Function(ChatMessage message);
/// TCP 文件元信息接收回调（peerId 为对方的设备 ID）
typedef OnFileMetaReceived = void Function(
    String transferId, String fileName, int fileSize, String peerId);
/// TCP 文件数据块接收回调
typedef OnFileChunkReceived = void Function(String transferId, List<int> chunk);
/// TCP 文件传输完成回调
typedef OnFileDoneReceived = void Function(String transferId);
/// TCP 日志回调
typedef OnLog = void Function(String log);
/// 新 peer 连接回调（ip/tcpPort 来自对方握手消息）
typedef OnPeerConnected = void Function(String peerId, String ip, int tcpPort);
/// peer 断开回调
typedef OnPeerDisconnected = void Function(String peerId);

/// 已连接的 peer 信息
class _PeerInfo {
  final Socket socket;
  final String ip;
  String? peerId;
  int tcpPort = 0;
  int msgLen = -1; // 当前帧数据长度，跨 TCP 包保持
  int? frameType; // 当前帧类型（kJsonMarker/kFileMarker）
  String? currentTransferId; // 当前文件传输 ID（file_meta 之后有效）

  _PeerInfo({required this.socket, required this.ip});
}

/// 本地 TCP 服务器
/// 监听端口，接收其他设备发来的消息和文件，并支持双向通信
class ChatServer {
  ServerSocket? _serverSocket;
  bool _isRunning = false;
  final Map<String, _PeerInfo> _connectedPeers = {}; // peerId -> peer info
  final List<_PeerInfo> _pendingPeers = []; // 尚未识别 peerId 的连接

  OnMessageReceived? onMessage;
  OnFileMetaReceived? onFileMeta;
  OnFileChunkReceived? onFileChunk;
  OnFileDoneReceived? onFileDone;
  OnPeerConnected? onPeerConnected;
  OnPeerDisconnected? onPeerDisconnected;
  OnLog? onLog;

  int get port => _serverSocket?.port ?? 0;
  bool get isRunning => _isRunning;

  /// 获取所有已连接的 peer ID
  List<String> get connectedPeerIds => _connectedPeers.keys.toList();

  /// 检查某 peer 是否已连接我们的服务器
  bool isPeerConnected(String peerId) => _connectedPeers.containsKey(peerId);

  /// 候选端口数量:默认端口被占用时,依次尝试后续连续端口,尽量保持端口可预期
  static const int _portCandidateCount = 20;

  /// 启动 TCP 服务器
  ///
  /// 优先尝试 [port] 起的连续候选端口,全部被占用时才回退到系统随机空闲端口,
  /// 避免端口冲突时聊天端口完全不可预期(真实端口会随心跳广播给对方)。
  Future<int> start({int port = 19423}) async {
    if (_isRunning) return port;

    for (var candidate = port; candidate < port + _portCandidateCount; candidate++) {
      try {
        return await _bindAndListen(candidate);
      } catch (e) {
        debugPrint('[ChatServer] Bind port $candidate failed: $e');
      }
    }

    // 候选端口全部被占用,回退到系统随机空闲端口
    debugPrint(
        '[ChatServer] Ports $port-${port + _portCandidateCount - 1} all occupied, fallback to random port');
    return _bindAndListen(0);
  }

  Future<int> _bindAndListen(int port) async {
    _serverSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
    );
    _isRunning = true;

    _serverSocket!.listen(
      _handleClient,
      onError: (error) {
        debugPrint('[ChatServer] Error: $error');
      },
    );

    debugPrint('[ChatServer] Listening on port ${_serverSocket!.port}');
    return _serverSocket!.port;
  }

  /// 停止服务器
  void stop() {
    _isRunning = false;
    for (final peer in _connectedPeers.values) {
      peer.socket.close();
    }
    _connectedPeers.clear();
    for (final peer in _pendingPeers) {
      peer.socket.close();
    }
    _pendingPeers.clear();
    _serverSocket?.close();
    _serverSocket = null;
    debugPrint('[ChatServer] Stopped');
  }

  /// 向已连接的 peer 发送消息，成功返回 true（连接失效返回 false）
  bool sendMessage(String peerId, ChatMessage msg) {
    final peer = _connectedPeers[peerId];
    if (peer == null) {
      debugPrint('[ChatServer] sendMessage FAILED: $peerId not connected');
      return false;
    }
    debugPrint(
        '[ChatServer] sendMessage to $peerId: type=${msg.type.name} content=${msg.content}');
    return _sendJson(peer.socket, msg.toJson());
  }

  /// 向已连接的 peer 发送 JSON 数据（'J' 标记 + TLV 格式），成功返回 true
  bool _sendJson(Socket socket, Map<String, dynamic> json) {
    try {
      final data = utf8.encode(jsonEncode(json));
      final header = <int>[
        kJsonMarker,
        (data.length >> 24) & 0xFF,
        (data.length >> 16) & 0xFF,
        (data.length >> 8) & 0xFF,
        data.length & 0xFF,
      ];
      socket.add(header);
      socket.add(data);
      socket.flush();
      return true;
    } catch (e, st) {
      debugPrint('[ChatServer] Send error: $e\n$st');
      return false;
    }
  }

  /// 仅当该 peer 仍映射到本连接时才移除，
  /// 避免旧连接的 onDone/onError 误删新建立的同 peer 连接
  void _removePeerIfCurrent(_PeerInfo peerInfo) {
    final id = peerInfo.peerId;
    if (id != null && identical(_connectedPeers[id], peerInfo)) {
      _connectedPeers.remove(id);
      onPeerDisconnected?.call(id);
    }
  }

  /// 通过已连接的 peer socket 发送文件（服务端通道）
  /// 先发元信息，再发文件内容，格式与 ChatClient.sendFile 一致
  Stream<double> sendFile({
    required String peerId,
    required String transferId,
    required String filePath,
    required String fileName,
    required int fileSize,
  }) async* {
    final peer = _connectedPeers[peerId];
    if (peer == null) {
      debugPrint('[ChatServer] Cannot send file to $peerId: not connected');
      return;
    }
    final socket = peer.socket;

    // 发送文件元信息
    _sendJson(socket, {
      'type': 'file_meta',
      'id': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
    });
    await Future.delayed(const Duration(milliseconds: 100));

    // 发送文件内容
    try {
      final file = File(filePath);
      final totalBytes = await file.length();
      var sentBytes = 0;

      final stream = file.openRead();
      await for (final chunk in stream) {
        // 文件数据块：'F' 标记 + 4字节长度 + 原始数据
        final size = chunk.length;
        final header = <int>[
          kFileMarker,
          (size >> 24) & 0xFF,
          (size >> 16) & 0xFF,
          (size >> 8) & 0xFF,
          size & 0xFF,
        ];

        socket.add(header);
        socket.add(chunk);
        await socket.flush();

        sentBytes += chunk.length;
        yield totalBytes > 0 ? sentBytes / totalBytes : 0.0;
      }

      // 发送完成标记
      _sendJson(socket, {'type': 'file_done', 'id': transferId});
      debugPrint('[ChatServer] File sent to $peerId: $fileName');
    } catch (e) {
      _sendJson(socket, {'type': 'file_error', 'id': transferId, 'error': e.toString()});
      debugPrint('[ChatServer] File send error: $e');
      // 抛给上层,让发送方消息能标记为失败
      rethrow;
    }
  }

  /// 处理客户端连接
  void _handleClient(Socket client) {
    final remoteAddr = '${client.remoteAddress.address}:${client.remotePort}';
    final ip = client.remoteAddress.address;
    debugPrint('[ChatServer] Client connected: $remoteAddr');

    final peerInfo = _PeerInfo(socket: client, ip: ip);
    _pendingPeers.add(peerInfo);

    // 重置缓冲区，每个客户端独立
    final buffer = <int>[];

    client.listen(
      (data) {
        buffer.addAll(data);
        _processBuffer(client, buffer, remoteAddr, peerInfo);
      },
      onDone: () {
        debugPrint('[ChatServer] Client disconnected: $remoteAddr');
        _pendingPeers.remove(peerInfo);
        _removePeerIfCurrent(peerInfo);
      },
      onError: (error) {
        debugPrint('[ChatServer] Client error: $error');
        _pendingPeers.remove(peerInfo);
        _removePeerIfCurrent(peerInfo);
      },
    );
  }

  /// 处理缓冲区中的数据（标记 + TLV 格式，支持跨包解析）
  void _processBuffer(Socket client, List<int> buffer, String remoteAddr, _PeerInfo peerInfo) {
    while (true) {
      if (peerInfo.frameType == null) {
        if (buffer.length < 5) break; // 1 标记 + 4 长度
        peerInfo.frameType = buffer[0];
        peerInfo.msgLen = (buffer[1] << 24) |
            (buffer[2] << 16) |
            (buffer[3] << 8) |
            buffer[4];
        buffer.removeRange(0, 5);
      }

      if (buffer.length < peerInfo.msgLen) break;

      final chunk = buffer.sublist(0, peerInfo.msgLen);
      buffer.removeRange(0, peerInfo.msgLen);
      final frameType = peerInfo.frameType!;
      peerInfo.msgLen = -1;
      peerInfo.frameType = null;

      // 文件数据块：不解析 JSON，直接回调
      if (frameType == kFileMarker) {
        final tid = peerInfo.currentTransferId;
        if (tid != null) {
          debugPrint('[ChatServer] file chunk from $remoteAddr: transfer=$tid ${chunk.length}B');
          onFileChunk?.call(tid, chunk);
        } else {
          debugPrint('[ChatServer] file chunk dropped: no active transfer');
        }
        continue;
      }

      try {
        final json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
        final type = json['type'] as String? ?? '';
        debugPrint(
            '[ChatServer] recv from $remoteAddr: type=$type senderId=${json['senderId']} len=${chunk.length}');

        // 识别 peer ID：从消息中提取 senderId 并注册
        if (peerInfo.peerId == null && json['senderId'] != null) {
          final senderId = json['senderId'] as String;
          peerInfo.peerId = senderId;
          peerInfo.tcpPort = json['tcpPort'] as int? ?? 0;
          _pendingPeers.remove(peerInfo);
          _connectedPeers[senderId] = peerInfo;
          debugPrint('[ChatServer] Peer identified: $senderId from $remoteAddr');
          onPeerConnected?.call(senderId, peerInfo.ip, peerInfo.tcpPort);
        }

        switch (type) {
          case 'hello':
            // 握手消息，仅用于识别 peer，不转发为聊天消息
            break;
          case 'text':
          case 'system':
            final msg = ChatMessage.fromJson(json);
            debugPrint('[ChatServer] onMessage -> peerId=${msg.senderId} content=${msg.content}');
            onMessage?.call(msg);
            break;
          case 'file_meta':
            peerInfo.currentTransferId = json['id'] as String? ?? '';
            onFileMeta?.call(
              json['id'] as String? ?? '',
              json['fileName'] as String? ?? '',
              json['fileSize'] as int? ?? 0,
              peerInfo.peerId ?? '',
            );
            break;
          case 'file_done':
            debugPrint('[ChatServer] file_done from $remoteAddr: ${json['id']}');
            onFileDone?.call(json['id'] as String? ?? '');
            break;
          case 'file_error':
            debugPrint('[ChatServer] file_error from $remoteAddr: ${json['error']}');
            onFileDone?.call(json['id'] as String? ?? '');
            break;
          default:
            debugPrint('[ChatServer] Unknown message type: $type');
        }
      } catch (e, st) {
        debugPrint('[ChatServer] Parse error: $e\n$st');
      }
    }
  }

  void dispose() {
    stop();
  }
}