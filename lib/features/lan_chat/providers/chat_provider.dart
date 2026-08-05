import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/lan_device.dart';
import '../repositories/chat_repository.dart';
import '../services/chat_server.dart';
import '../services/chat_client.dart';
import '../services/receive_directory.dart';

/// 聊天状态管理
class ChatProvider extends ChangeNotifier {
  final ChatRepository _repository = ChatRepository();
  final ChatServer _server = ChatServer();
  final Map<String, ChatClient> _clients = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, FileTransferInfo> _fileTransfers = {};
  final Map<String, List<int>> _receiveBuffers = {}; // transferId -> 接收中的文件数据
  final Map<String, String> _transferPeers = {}; // transferId -> 对方设备 ID
  final Map<String, String> _transferMessageIds = {}; // transferId -> 发送方消息 ID
  final String _selfId;
  String _selfName;
  bool _isServerRunning = false;

  ChatProvider({required String selfId, String? selfName})
      : _selfId = selfId,
        _selfName = selfName ?? 'Unknown';

  String get selfId => _selfId;
  String get selfName => _selfName;
  int get tcpPort => _server.port;
  List<Map<String, dynamic>> get peers => _repository.getPeers();

  // 服务器消息流
  final StreamController<ChatMessage> _messageController =
      StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onMessageReceived => _messageController.stream;

  /// 更新用户名
  void setSelfName(String name) {
    if (name.trim().isEmpty) return;
    _selfName = name.trim();
    notifyListeners();
  }

  /// 启动 TCP 服务器
  Future<int> startServer({int port = 19423}) async {
    if (_isServerRunning) return _server.port;

    _server.onMessage = (msg) {
      _handleIncomingMessage(msg, msg.senderId);
    };

    _server.onFileMeta = (transferId, fileName, fileSize, peerId) {
      _handleIncomingFileMeta(transferId, fileName, fileSize, peerId);
    };

    _server.onFileChunk = (transferId, chunk) {
      _receiveFileChunk(transferId, chunk);
    };

    _server.onFileDone = (transferId) {
      _finalizeFileReceive(transferId);
    };

    _server.onPeerConnected = (peerId, _, _) {
      // 单连接模型：不再自动回连，仅做竞态收敛
      _convergeSingleConnection(peerId);
    };

    _server.onPeerDisconnected = (_) {
      notifyListeners();
    };

    _server.onLog = (log) {
      debugPrint('[ChatServer] $log');
    };

    final actualPort = await _server.start(port: port);
    _isServerRunning = true;
    debugPrint('[ChatProvider] Server started on port $actualPort (selfId=$_selfId)');
    return actualPort;
  }

  /// 停止服务器
  void stopServer() {
    _server.stop();
    _isServerRunning = false;
  }

  /// 连接到设备
  Future<bool> connectToDevice(LanDevice device) async {
    debugPrint(
        '[ChatProvider] connectToDevice: id=${device.id} ip=${device.ip} port=${device.port}');
    // 单连接模型：对方已连到我们的服务器时，直接复用 server 通道，不再建第二条连接
    if (_server.isPeerConnected(device.id)) {
      debugPrint('[ChatProvider] connectToDevice: ${device.id} already in our server, reuse channel');
      return true;
    }

    final existing = _clients[device.id];
    if (existing != null && existing.isConnected) {
      debugPrint('[ChatProvider] connectToDevice: existing client connected for ${device.id}');
      return true;
    }

    // 丢弃已断开的旧客户端
    if (existing != null) {
      debugPrint('[ChatProvider] connectToDevice: disposing stale client for ${device.id}');
      existing.dispose();
      _clients.remove(device.id);
    }

    final client = ChatClient();
    client.onMessage = (msg) {
      _handleIncomingMessage(msg, msg.senderId);
    };
    client.onFileMeta = (transferId, fileName, fileSize, _) {
      _handleIncomingFileMeta(transferId, fileName, fileSize, device.id);
    };
    client.onFileChunk = (transferId, chunk) {
      _receiveFileChunk(transferId, chunk);
    };
    client.onFileDone = (transferId) {
      _finalizeFileReceive(transferId);
    };
    final success = await client.connect(device.ip, device.port);

    if (success) {
      _clients[device.id] = client;
      debugPrint('[ChatProvider] connectToDevice OK: ${device.id}');
      // 发送握手消息，让对方服务器立即识别我们，实现双向通信
      client.sendHello(_selfId, _selfName, _server.port);
      notifyListeners();
    } else {
      debugPrint('[ChatProvider] connectToDevice FAILED: ${device.id}');
    }

    return success;
  }

  /// 对方连到我们的服务器时，收敛为单连接：
  /// 若我们已有一个连向对方的客户端（说明双方几乎同时发起连接），
  /// 由 id 更大的一方放弃自己的客户端，保留对方发起的 server 通道，
  /// 避免同一对设备之间出现两条 TCP 连接。
  void _convergeSingleConnection(String peerId) {
    final client = _clients[peerId];
    if (client != null && client.isConnected && _selfId.compareTo(peerId) > 0) {
      client.dispose();
      _clients.remove(peerId);
    }
    notifyListeners();
  }

  /// 发送文本消息
  void sendTextMessage(LanDevice target, String text) {
    final msg = ChatMessage(
      id: const Uuid().v4(),
      senderId: _selfId,
      senderName: _selfName,
      type: MessageType.text,
      content: text,
      timestamp: DateTime.now(),
      isMe: true,
      sendStatus: SendStatus.sending,
    );

    // 保存到本地
    _saveMessage(msg, target.id);
    notifyListeners();

    // 发送
    _sendToDevice(target, msg, target.id);
  }

  /// 发送文件
  void sendFile({
    required LanDevice target,
    required String filePath,
    required String fileName,
    required int fileSize,
  }) {
    final transferId = const Uuid().v4();
    final transferInfo = FileTransferInfo(
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      direction: TransferDirection.send,
      status: TransferStatus.pending,
    );
    _fileTransfers[transferId] = transferInfo;

    // 立即生成发送方的文件消息,让发送方马上看到"发送中"状态
    final msg = ChatMessage(
      id: const Uuid().v4(),
      senderId: _selfId,
      senderName: _selfName,
      type: MessageType.file,
      content: _encodeFileContent(fileName, fileSize, transferId,
          path: filePath),
      timestamp: DateTime.now(),
      isMe: true,
      sendStatus: SendStatus.sending,
    );
    _transferMessageIds[transferId] = msg.id;
    _saveMessage(msg, target.id);
    notifyListeners();

    _sendFileToDevice(target, transferId, filePath, fileName, fileSize);
  }

  /// 获取与某个设备的聊天客户端
  ChatClient? getClient(String peerId) => _clients[peerId];

  /// 是否已连接到某个设备（server 通道或客户端通道任一可用）
  bool isConnectedTo(String peerId) =>
      _server.isPeerConnected(peerId) ||
      (_clients[peerId]?.isConnected ?? false);

  /// 获取与某个设备的聊天记录
  List<ChatMessage> getMessages(String peerId) {
    if (_messages.containsKey(peerId)) {
      return List.unmodifiable(_messages[peerId]!);
    }
    // 从数据库加载
    final history = _repository.getMessages(peerId);
    _messages[peerId] = history;
    return List.unmodifiable(history);
  }

  /// 获取文件传输状态
  FileTransferInfo? getFileTransfer(String transferId) {
    return _fileTransfers[transferId];
  }

  /// 标记已读
  void markRead(String peerId) {
    _repository.markRead(peerId);
    notifyListeners();
  }

  /// 发送消息到设备
  void _sendToDevice(LanDevice target, ChatMessage msg, String peerId) {
    // 优先：对方已连接我们的服务器时，通过同一连接回写
    if (_server.isPeerConnected(target.id) &&
        _server.sendMessage(target.id, msg)) {
      debugPrint('[ChatProvider] send via server channel -> ${target.id}');
      _updateSendStatus(peerId, msg.id, SendStatus.sent);
      return;
    }
    // server 通道已失效时回退到客户端通道

    final client = _clients[target.id];
    if (client != null && client.isConnected) {
      debugPrint('[ChatProvider] send via client channel -> ${target.id}');
      client.sendMessage(msg);
      _updateSendStatus(peerId, msg.id, SendStatus.sent);
    } else {
      // 自动重新连接
      debugPrint('[ChatProvider] no channel to ${target.id}, reconnect...');
      connectToDevice(target).then((ok) {
        if (ok) {
          debugPrint('[ChatProvider] reconnected, send -> ${target.id}');
          _clients[target.id]?.sendMessage(msg);
          _updateSendStatus(peerId, msg.id, SendStatus.sent);
        } else {
          debugPrint('[ChatProvider] reconnect FAILED -> ${target.id}');
          _updateSendStatus(peerId, msg.id, SendStatus.failed);
        }
      });
    }
  }

  void _updateSendStatus(String peerId, String msgId, SendStatus status) {
    final msgs = _messages[peerId];
    if (msgs == null) return;
    final idx = msgs.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    msgs[idx] = msgs[idx].copyWith(sendStatus: status);
    notifyListeners();
  }

  /// 发送文件到设备
  void _sendFileToDevice(
    LanDevice target,
    String transferId,
    String filePath,
    String fileName,
    int fileSize,
  ) async {
    // 1) server 通道：对方已连到我们，通过同一连接发送
    if (_server.isPeerConnected(target.id)) {
      final stream = _server.sendFile(
        peerId: target.id,
        transferId: transferId,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
      );
      await _finishFileSend(stream, target.id, transferId);
      return;
    }

    // 2) 客户端通道：没有可用连接时先建立
    var client = _clients[target.id];
    if (client == null || !client.isConnected) {
      final ok = await connectToDevice(target);
      if (!ok) return;
      client = _clients[target.id];
    }

    if (client == null || !client.isConnected) {
      // 通道不可用，标记失败而不是崩溃
      _updateFileSendResult(transferId, target.id,
          success: false, error: '连接不可用');
      return;
    }

    final stream = client.sendFile(
      transferId: transferId,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
    );
    await _finishFileSend(stream, target.id, transferId);
  }

  /// 跟踪文件发送进度并完成收尾(更新消息状态为发送成功/失败)
  Future<void> _finishFileSend(
    Stream<double> stream,
    String peerId,
    String transferId,
  ) async {
    try {
      await for (final progress in stream) {
        final info = _fileTransfers[transferId];
        if (info != null) {
          _fileTransfers[transferId] = info.copyWith(
            status: TransferStatus.transferring,
            progress: progress,
          );
          notifyListeners();
        }
      }
      // 流正常结束 = 发送成功
      _updateFileSendResult(transferId, peerId, success: true);
    } catch (e) {
      // 发送失败(连接断开/文件不可读等)
      debugPrint('[ChatProvider] file send FAILED: $e');
      _updateFileSendResult(transferId, peerId, success: false, error: e.toString());
    }
  }

  /// 更新文件发送结果:传输状态 + 消息的发送状态
  void _updateFileSendResult(
    String transferId,
    String peerId, {
    required bool success,
    String? error,
  }) {
    final info = _fileTransfers[transferId];
    if (info != null) {
      _fileTransfers[transferId] = info.copyWith(
        status: success ? TransferStatus.done : TransferStatus.failed,
        progress: success ? 1.0 : info.progress,
        errorMessage: error,
      );
    }
    final msgId = _transferMessageIds[transferId];
    if (msgId != null) {
      _updateSendStatus(
          peerId, msgId, success ? SendStatus.sent : SendStatus.failed);
    }
    notifyListeners();
  }

  /// 处理收到的消息
  void _handleIncomingMessage(ChatMessage msg, String peerId) {
    debugPrint(
        '[ChatProvider] incoming from $peerId: type=${msg.type.name} content=${msg.content}');
    _saveMessage(msg, peerId);
    _messageController.add(msg);
    notifyListeners();
  }

  /// 处理收到的文件元信息
  void _handleIncomingFileMeta(
      String transferId, String fileName, int fileSize, String peerId) {
    final info = FileTransferInfo(
      fileName: fileName,
      fileSize: fileSize,
      direction: TransferDirection.receive,
      status: TransferStatus.pending,
    );
    _fileTransfers[transferId] = info;
    _transferPeers[transferId] = peerId;
    _receiveBuffers[transferId] = [];
    debugPrint(
        '[ChatProvider] file_meta: transfer=$transferId name=$fileName size=$fileSize peer=$peerId');
    notifyListeners();
  }

  /// 接收文件数据块
  void _receiveFileChunk(String transferId, List<int> chunk) {
    _receiveBuffers[transferId]?.addAll(chunk);
    final info = _fileTransfers[transferId];
    if (info != null) {
      final total = _receiveBuffers[transferId]!.length;
      _fileTransfers[transferId] = info.copyWith(
        status: TransferStatus.transferring,
        progress: info.fileSize > 0
            ? (total / info.fileSize).clamp(0.0, 1.0)
            : 0.0,
      );
      notifyListeners();
    }
  }

  /// 文件接收完成：落盘并生成消息记录
  Future<void> _finalizeFileReceive(String transferId) async {
    final info = _fileTransfers[transferId];
    final bytes = _receiveBuffers.remove(transferId);
    final peerId = _transferPeers.remove(transferId) ?? '';
    if (info == null || bytes == null || bytes.isEmpty) {
      debugPrint('[ChatProvider] finalize receive FAILED: transfer=$transferId data missing');
      return;
    }

    try {
      // 按平台策略保存到免权限、用户可访问的目录(Android 为系统"下载"目录)
      final location = await ReceiveDirectory.saveReceivedFile(bytes, info.fileName);
      debugPrint('[ChatProvider] file received: $location');

      final msg = ChatMessage(
        id: const Uuid().v4(),
        senderId: peerId,
        senderName: '',
        type: MessageType.file,
        content: _encodeFileContent(info.fileName, info.fileSize, transferId,
            path: location),
        timestamp: DateTime.now(),
      );
      _saveMessage(msg, peerId);
      _messageController.add(msg);

      _fileTransfers[transferId] = info.copyWith(
        status: TransferStatus.done,
        progress: 1.0,
      );
    } catch (e, st) {
      debugPrint('[ChatProvider] finalize receive error: $e\n$st');
      _fileTransfers[transferId] = info.copyWith(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  /// 保存消息到内存和数据库
  void _saveMessage(ChatMessage msg, String peerId) {
    _messages.putIfAbsent(peerId, () => []);
    _messages[peerId]!.add(msg);
    _repository.saveMessage(msg, peerId);
  }

  /// 编码文件内容为 JSON 字符串
  String _encodeFileContent(String fileName, int fileSize, String transferId,
      {String? path}) {
    return jsonEncode({
      'fileName': fileName,
      'fileSize': fileSize,
      'transferId': transferId,
      'path': ?path,
    });
  }

  @override
  void dispose() {
    stopServer();
    for (final client in _clients.values) {
      client.dispose();
    }
    _clients.clear();
    _messageController.close();
    super.dispose();
  }
}