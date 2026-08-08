import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/file_transfer_session.dart';
import '../models/lan_device.dart';
import '../repositories/chat_repository.dart';
import '../services/chat_server.dart';
import '../services/chat_client.dart';
import '../services/receive_directory.dart';
import '../services/screen_keep_on.dart';

/// 聊天状态管理
class ChatProvider extends ChangeNotifier {
  final ChatRepository _repository = ChatRepository();
  final ChatServer _server = ChatServer();
  final Map<String, ChatClient> _clients = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, FileTransferSession> _fileTransfers = {};
  // ---- 接收侧 .part 流式落盘状态(替代原内存 List<int> 缓冲)----
  final Map<String, RandomAccessFile> _receiveWriters = {}; // transferId -> 打开的追加写句柄
  final Map<String, String> _receivePartPaths = {}; // transferId -> .part 路径
  final Map<String, int> _receiveOffsets = {}; // transferId -> 已落盘字节数
  final Map<String, BytesBuilder> _receivePending = {}; // writer 就绪前/写入中的缓冲(BytesBuilder 低拷贝累积)
  final Map<String, bool> _receiveWriting = {}; // 防止同一 transfer 并发写入乱序
  final Map<String, String> _transferPeers = {}; // transferId -> 对方设备 ID
  final Map<String, String> _transferMessageIds = {}; // transferId -> 发送方消息 ID
  // ---- 小文件快速通道:内存缓冲直接落盘(不建 .part、不存断点索引)----
  final Map<String, BytesBuilder> _receiveSmallBuffers = {}; // transferId -> 累积字节
  // ---- 接收等待缓冲软上限:writer 未就绪时暂存数据的最大字节数 ----
  static const int _receivePendingLimit = 64 * 1024 * 1024; // 64MB
  // ---- 接收背压高水位:暂存超过该值即暂停对端 socket 读取 ----
  // (TCP 窗口填满 → 发送方 flush 阻塞自然减速,替代堆积到 64MB 再 abort;
  // 排空后恢复读取,数据继续流动)
  static const int _receivePendingHighWater = 24 * 1024 * 1024; // 24MB
  // ---- 接收侧通道来源(决定 file_ready 回复走 server 还是 client 通道)----
  final Map<String, bool> _receiveViaServer = {}; // transferId -> 是否经 server 通道接收
  final Map<String, DateTime> _prepareStartedAt = {}; // transferId -> 开始准备 .part 的时间(诊断超时)

  // ---- 批量发送队列 ----
  final List<String> _sendQueue = []; // 等待发送的 transferId(小文件 insert(0) 插队)
  // 串行发送(方案 A):一次只传一个文件,完成后再传下一个。
  // 背景:单连接多文件并发时,TCP 只提供连接级背压、没有逐传输流控,
  // 接收端 writer 未就绪时 chunk 只能暂存内存,曾反复触发 pending 溢出 abort
  // (多文件只收到 1 个)。串行后 writer 永远先于 chunk 就绪,该整类 bug 消失;
  // 局域网单连接本就能跑满带宽,串行吞吐损失可忽略,小文件仍可插队优先。
  static const int _maxConcurrentSends = 1; // 同时进行的发送上限(串行=1)
  int _activeSends = 0; // 当前正在发送的数量
  // ---- 发送看门狗:防止传输卡死导致 UI 永久转圈/队列被阻塞 ----
  final Map<String, DateTime> _sendStartedAt = {}; // transferId -> 开始发送时间
  final Map<String, DateTime> _sendLastProgressAt = {}; // transferId -> 最近产出进度时间
  final Map<String, DateTime> _receiveLastProgressAt = {}; // transferId -> 最近落盘/缓冲时间
  // 屏幕常亮持有标志:发送队列有任务时点亮,全部结束后熄灭
  bool _screenOnHeld = false;
  static const Duration _sendWatchdogInterval = Duration(seconds: 5);
  static const Duration _sendWatchdogTimeout = Duration(seconds: 45); // 从未产出进度
  static const Duration _transferStallTimeout = Duration(seconds: 45); // 传输中零进展
  Timer? _sendWatchdogTimer;
  final Map<String, LanDevice> _sendTargets = {}; // transferId -> 目标设备(排队后使用)
  final Map<String, Stream<List<int>>> _sendStreams = {}; // transferId -> 一次性流式源(替代文件路径)
  final Map<String, Stream<List<int>> Function(int offset)> _sendStreamFactories = {}; // transferId -> 可重开流工厂(原生直读流,从头重开读取)
  final String _selfId;
  String _selfName;
  bool _isServerRunning = false;

  /// 是否正在重连(发送/文件传输前建连失败时置位,供 UI 提示"重连中...")
  bool _isReconnecting = false;
  bool get isReconnecting => _isReconnecting;

  /// 传输进度通知节流:避免大文件传输时每个 chunk(约 64KB)都触发全量重建
  DateTime? _lastTransferNotifyAt;
  static const Duration _transferNotifyInterval = Duration(milliseconds: 150);

  /// 距上次传输进度通知超过间隔时返回 true,并刷新时间戳
  bool _shouldNotifyTransferProgress() {
    final now = DateTime.now();
    if (_lastTransferNotifyAt == null ||
        now.difference(_lastTransferNotifyAt!) >= _transferNotifyInterval) {
      _lastTransferNotifyAt = now;
      return true;
    }
    return false;
  }

  ChatProvider({required String selfId, String? selfName})
      : _selfId = selfId,
        _selfName = selfName ?? 'Unknown' {
    // 发送看门狗:周期检查卡死的发送(从未产出进度且超时),自动失败并继续泵队列,
    // 保证任何情况下 UI 都不会"永久转圈"、队列不会被一个僵尸传输卡死
    _sendWatchdogTimer = Timer.periodic(
        _sendWatchdogInterval, (_) => _checkSendWatchdog());
  }

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
      _handleIncomingFileMeta(transferId, fileName, fileSize, peerId,
          viaServer: true);
    };

    _server.onFileChunk = (transferId, chunk) {
      _receiveFileChunk(transferId, chunk);
    };

    _server.onFileDone = (transferId, md5) {
      _finalizeFileReceive(transferId, md5);
    };

    _server.onFileError = (transferId, error) {
      _handleReceiveFileError(transferId, error);
    };

    _server.onFileControl = (transferId, action) {
      _handleFileControl(transferId, action);
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
      _handleIncomingFileMeta(transferId, fileName, fileSize, device.id,
          viaServer: false);
    };
    client.onFileChunk = (transferId, chunk) {
      _receiveFileChunk(transferId, chunk);
    };
    client.onFileDone = (transferId, md5) {
      _finalizeFileReceive(transferId, md5);
    };
    client.onFileError = (transferId, error) {
      _handleReceiveFileError(transferId, error);
    };
    client.onFileControl = (transferId, action) {
      _handleFileControl(transferId, action);
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

  /// 发送文件(加入批量队列,受并发上限约束)
  /// [filePath] 可为空(流式源场景);[readStream] 提供按块读取的流,
  /// 有流时发送侧直接消费流,避免依赖真实文件路径。
  /// [readStreamFactory] 提供"可重开"的流式源(Android/iOS 原生直读流):
  /// 每次发送/重试时从头重新打开流;与 [readStream](一次性流)二选一,优先使用工厂。
  void sendFile({
    required LanDevice target,
    String? filePath,
    required String fileName,
    required int fileSize,
    Stream<List<int>>? readStream,
    Stream<List<int>> Function(int offset)? readStreamFactory,
  }) {
    final transferId = const Uuid().v4();
    final session = FileTransferSession(
      transferId: transferId,
      info: FileTransferInfo(
        fileName: fileName,
        fileSize: fileSize,
        filePath: filePath,
        direction: TransferDirection.send,
        status: TransferStatus.pending,
      ),
    );
    _fileTransfers[transferId] = session;
    if (readStream != null) {
      _sendStreams[transferId] = readStream;
    }
    if (readStreamFactory != null) {
      _sendStreamFactories[transferId] = readStreamFactory;
    }

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

    // 入队等待发送(受并发上限控制)
    _sendTargets[transferId] = target;
    // 小文件插队优先,避免被前面的大文件长时间阻塞
    if (fileSize <= kSmallFileThresholdBytes) {
      _sendQueue.insert(0, transferId);
    } else {
      _sendQueue.add(transferId);
    }
    _pumpSendQueue();
  }

  /// 批量发送队列泵:并发未满时逐个启动
  void _pumpSendQueue() {
    while (_activeSends < _maxConcurrentSends && _sendQueue.isNotEmpty) {
      final transferId = _sendQueue.removeAt(0);
      final target = _sendTargets[transferId];
      final session = _fileTransfers[transferId];
      if (target == null || session == null) continue;
      _activeSends++;
      _sendStartedAt[transferId] = DateTime.now();
      final info = session.info;
      _sendFileToDevice(
        target,
        transferId,
        info.filePath ?? '',
        info.fileName,
        info.fileSize,
      );
    }
    // 队列状态可能变化(新任务/任务结束),同步屏幕常亮状态
    _syncScreenOn();
  }

  /// 按发送活跃数/队列长度/接收会话同步屏幕常亮(幂等):
  /// 有排队/正在发送/正在接收 → 点亮;全部结束后 → 熄灭,恢复系统熄屏策略。
  void _syncScreenOn() {
    // 接收中:存在 pending/transferring 状态的接收会话
    final receiving = _fileTransfers.values.any((t) =>
        t.direction == TransferDirection.receive &&
        (t.status == TransferStatus.pending ||
            t.status == TransferStatus.transferring));
    final need = _activeSends > 0 || _sendQueue.isNotEmpty || receiving;
    if (need == _screenOnHeld) return;
    _screenOnHeld = need;
    if (need) {
      ScreenKeepOn.acquire();
    } else {
      ScreenKeepOn.release();
    }
  }

  /// 所有传输会话(供传输列表 UI 使用)
  List<FileTransferSession> get transfers => _fileTransfers.values.toList();

  /// 指定会话的传输会话(按发送目标/接收来源关联 peerId)。
  /// 发送方向经 [_sendTargets] 关联,接收方向经 [_transferPeers] 关联;
  /// 已完成发送会移除 target,故只用于活动传输的展示过滤。
  List<FileTransferSession> transfersForPeer(String peerId) {
    return _fileTransfers.values.where((t) {
      final tid = t.transferId;
      if (t.direction == TransferDirection.send) {
        return _sendTargets[tid]?.id == peerId;
      }
      return _transferPeers[tid] == peerId;
    }).toList();
  }

  /// 取消传输:发送方向中止发送循环;接收方向清理 .part 并通知对方
  void cancelTransfer(String transferId) {
    final session = _fileTransfers[transferId];
    if (session == null) return;
    final peerId = _transferPeers[transferId];
    if (session.direction == TransferDirection.receive && peerId != null) {
      _sendFileControlToPeer(peerId, transferId, 'cancel');
    }
    // 若还在排队,移出队列
    _sendQueue.remove(transferId);
    _sendStreams.remove(transferId); // 取消后一次性流式源作废
    _sendStreamFactories.remove(transferId); // 取消后可重开工厂作废
    _sendStartedAt.remove(transferId);
    _sendLastProgressAt.remove(transferId);
    session.cancel();
    if (session.direction == TransferDirection.receive) {
      _cleanupReceivePart(transferId);
    } else {
      final msgId = _transferMessageIds[transferId];
      if (msgId != null) {
        _updateSendStatus(peerId ?? '', msgId, SendStatus.failed);
      }
      // 保留 target 供重试按钮使用;offset 归 0 让重试从头发送
      session.offset = 0;
    }
    _syncScreenOn();
    notifyListeners();
  }

  /// 重试发送:失败/取消的发送从已传偏移续传
  void retryTransfer(String transferId) {
    final session = _fileTransfers[transferId];
    final target = _sendTargets[transferId];
    if (session == null || target == null) return;
    if (session.direction != TransferDirection.send) return;
    // 重试依赖可重开的源:真实文件路径,或可重开流工厂(原生直读流)。
    // 一次性流(file_picker withReadStream)已被消费,无法重试。
    final hasFactory = _sendStreamFactories.containsKey(transferId);
    final hasPath =
        session.info.filePath != null && session.info.filePath!.isNotEmpty;
    if (!hasFactory && !hasPath) {
      session.update(status: TransferStatus.failed, errorMessage: '流式源已消费,无法重试');
      final msgId = _transferMessageIds[transferId];
      if (msgId != null) {
        _updateSendStatus(target.id, msgId, SendStatus.failed);
      }
      notifyListeners();
      return;
    }
    // 无断点续传,重试一律从头发送
    session.offset = 0;
    // 重置为待发送并重新入队(从头发送)
    session.update(
      status: TransferStatus.pending,
      progress: 0.0,
    );
    final msgId = _transferMessageIds[transferId];
    if (msgId != null) {
      _updateSendStatus(target.id, msgId, SendStatus.sending);
    }
    _sendQueue.add(transferId);
    _pumpSendQueue();
    notifyListeners();
  }

  /// 向对方发送文件控制消息(优先 server 通道,否则 client 通道)
  void _sendFileControlToPeer(String peerId, String transferId, String action) {
    if (_server.isPeerConnected(peerId)) {
      _server.sendFileControl(peerId, transferId, action);
      return;
    }
    _clients[peerId]?.sendFileControl(transferId, action);
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

  /// 获取文件传输会话(含进度、速度、剩余时间等运行时状态)
  FileTransferSession? getFileTransfer(String transferId) {
    return _fileTransfers[transferId];
  }

  /// 标记已读
  void markRead(String peerId) {
    _repository.markRead(peerId);
    notifyListeners();
  }

  /// 删除与某个 peer 的单条/多条消息(保留会话,删除后不可恢复)
  void deleteMessages(String peerId, List<String> ids) {
    if (ids.isEmpty) return;
    final msgs = _messages[peerId];
    if (msgs != null) {
      final idSet = ids.toSet();
      msgs.removeWhere((m) => idSet.contains(m.id));
    }
    _repository.deleteMessagesByIds(peerId, ids);
    notifyListeners();
  }

  /// 发送消息到设备
  /// 优先 server 通道;其次 client 通道;两者都不可用时自动重连
  /// (带"重连中"状态,失败自动重试 1 次),成功后才发送。
  void _sendToDevice(LanDevice target, ChatMessage msg, String peerId) {
    // 优先：对方已连接我们的服务器时，通过同一连接回写
    if (_server.isPeerConnected(target.id) &&
        _server.sendMessage(target.id, msg)) {
      debugPrint('[ChatProvider] send via server channel -> ${target.id}');
      _updateSendStatus(peerId, msg.id, SendStatus.sent);
      return;
    }

    final client = _clients[target.id];
    if (client != null && client.isConnected) {
      debugPrint('[ChatProvider] send via client channel -> ${target.id}');
      client.sendMessage(msg);
      _updateSendStatus(peerId, msg.id, SendStatus.sent);
      return;
    }

    // 连接异常:进入重连流程(UI 显示"重连中..."),成功后才补发
    debugPrint('[ChatProvider] no channel to ${target.id}, reconnecting...');
    _ensureConnection(target).then((ok) {
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

  /// 发送前确保连接可用(server/client 任一通道可用即通过);
  /// 不可用时尝试建连,失败自动重试 1 次(应对瞬时抖动)。
  /// 重连期间置位 [isReconnecting] 供 UI 提示"重连中..."。
  Future<bool> _ensureConnection(LanDevice target) async {
    if (_server.isPeerConnected(target.id) ||
        (_clients[target.id]?.isConnected ?? false)) {
      return true;
    }
    _isReconnecting = true;
    notifyListeners();
    try {
      var ok = await connectToDevice(target);
      if (!ok) {
        // 首次失败自动重试 1 次
        await Future.delayed(const Duration(milliseconds: 500));
        ok = await connectToDevice(target);
      }
      return ok;
    } finally {
      _isReconnecting = false;
      notifyListeners();
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
    String? filePath,
    String fileName,
    int fileSize,
  ) async {
    final session = _fileTransfers[transferId];
    // 可重开流工厂优先(Android/iOS 原生直读流):从头重开读取;
    // 否则使用一次性流
    final factory = _sendStreamFactories[transferId];
    final readStream =
        factory != null ? factory(0) : _sendStreams[transferId];

    // 取消或已失败(对方报错/校验失败)都停止推流:
    // 否则接收端 abort 清理后,发送端还会继续空推到文件读完
    // (表现为发送端一直有进度、接收端反复 pending overflow abort)
    bool isCancelled() =>
        session?.status == TransferStatus.cancelled ||
        session?.status == TransferStatus.failed;

    // 1) server 通道：对方已连到我们，通过同一连接发送
    if (_server.isPeerConnected(target.id)) {
      final stream = _server.sendFile(
        peerId: target.id,
        transferId: transferId,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        readStream: readStream,
        isCancelled: isCancelled,
      );
      await _finishFileSend(stream, target.id, transferId);
      return;
    }

    // 2) 客户端通道：没有可用连接时先建立(带重连与失败重试)
    var client = _clients[target.id];
    if (client == null || !client.isConnected) {
      final ok = await _ensureConnection(target);
      if (!ok) {
        // 连接失败:标记失败而不是卡在 pending,并释放并发槽继续泵队列
        _updateFileSendResult(transferId, target.id,
            success: false, error: '连接失败');
        if (_activeSends > 0) _activeSends--;
        _pumpSendQueue();
        return;
      }
      client = _clients[target.id];
    }

    // 重连期间用户可能已点了取消:取消后不再发送(避免"点叉号后仍重连重发")
    if (session?.status == TransferStatus.cancelled) {
      debugPrint('[ChatProvider] send cancelled during reconnect: $transferId');
      _updateFileSendResult(transferId, target.id, success: false, cancelled: true);
      if (_activeSends > 0) _activeSends--;
      _pumpSendQueue();
      return;
    }

    if (client == null || !client.isConnected) {
      // 通道不可用，标记失败而不是崩溃(并释放并发槽,继续泵队列)
      _updateFileSendResult(transferId, target.id,
          success: false, error: '连接不可用');
      if (_activeSends > 0) _activeSends--;
      _pumpSendQueue();
      return;
    }

    final stream = client.sendFile(
      transferId: transferId,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      readStream: readStream,
      isCancelled: isCancelled,
    );
    await _finishFileSend(stream, target.id, transferId);
  }

  /// 跟踪文件发送进度并完成收尾(更新消息状态为发送成功/失败/取消)
  Future<void> _finishFileSend(
    Stream<double> stream,
    String peerId,
    String transferId,
  ) async {
    try {
      await for (final progress in stream) {
        final session = _fileTransfers[transferId];
        if (session != null) {
          session.update(
            status: TransferStatus.transferring,
            progress: progress,
          );
          // 记录已传字节,供断点续传使用
          session.offset = (progress * session.fileSize).round();
          // 记录最近产出进度时间(停滞看门狗用)
          _sendLastProgressAt[transferId] = DateTime.now();
          // 进度通知节流;传输结束/失败路径(_updateFileSendResult)会兜底通知
          if (_shouldNotifyTransferProgress()) notifyListeners();
        }
      }
      // 流正常结束:取消则标记取消;对方已报失败则保持失败;
      // 从未产出进度(仍 pending)说明连接在发送前就失效,按失败处理;
      // 否则视为发送成功
      final session = _fileTransfers[transferId];
      if (session != null && session.status == TransferStatus.cancelled) {
        _updateFileSendResult(transferId, peerId, success: false, cancelled: true);
      } else if (session != null && session.status == TransferStatus.failed) {
        _updateFileSendResult(transferId, peerId,
            success: false, error: session.errorMessage ?? '对方中止了传输');
      } else if (session != null && session.status == TransferStatus.pending) {
        // 流结束但零进度:发送在开始前就中断(如 peer 连接已失效)
        _updateFileSendResult(transferId, peerId,
            success: false, error: '连接异常,未能开始传输');
      } else {
        _updateFileSendResult(transferId, peerId, success: true);
      }
    } catch (e) {
      // 发送失败(连接断开/文件不可读等)
      debugPrint('[ChatProvider] file send FAILED: $e');
      _updateFileSendResult(transferId, peerId, success: false, error: e.toString());
    } finally {
      // 流式源是一次性的,发送结束(成功/失败/取消)后即作废;
      // 后续重试回退到文件路径(filePath 为空则无法续传)
      _sendStreams.remove(transferId);
      _sendStartedAt.remove(transferId);
      _sendLastProgressAt.remove(transferId);
      // 释放并发槽,继续泵下一个排队任务
      if (_activeSends > 0) _activeSends--;
      _pumpSendQueue();
    }
  }

  /// 传输看门狗(发送侧 + 接收侧):
  /// - 发送从未产出进度(pending)超阈值 → 失败并释放并发槽;
  /// - 发送中零进展超阈值(熄屏挂起/原生直读流挂起/磁盘卡死)→ 失败并通知对端;
  /// - 对端已报失败但发送流未正常结束 → 立即释放并发槽继续队列;
  /// - 接收侧发送方卡死时收不到新 chunk → 中止并回发 file_error,让双方收敛。
  /// 保证任何情况下 UI 都不会永久冻结、队列不会被僵尸传输卡死。
  void _checkSendWatchdog() {
    final now = DateTime.now();
    for (final entry in _sendStartedAt.entries.toList()) {
      final tid = entry.key;
      final session = _fileTransfers[tid];
      if (session == null) {
        _sendStartedAt.remove(tid);
        _sendLastProgressAt.remove(tid);
        continue;
      }
      if (session.status == TransferStatus.pending) {
        // 从未产出进度(卡在握手/建连/流打开)
        if (now.difference(entry.value) > _sendWatchdogTimeout) {
          _failStuckSend(tid, '发送超时:对方未就绪或连接异常');
        }
      } else if (session.status == TransferStatus.transferring) {
        // 传输中零进展(熄屏挂起/原生流挂起/磁盘卡死)
        final last = _sendLastProgressAt[tid];
        if (last != null && now.difference(last) > _transferStallTimeout) {
          _failStuckSend(tid, '传输停滞,已中止(可重试续传)');
        }
      } else if (session.status == TransferStatus.failed ||
          session.status == TransferStatus.cancelled) {
        // 该状态仍留在 _sendStartedAt 说明发送流没有正常结束(卡在读取流上):
        // 立即释放并发槽继续队列,避免僵尸传输阻塞后续文件
        debugPrint('[ChatProvider] send watchdog: release stuck slot transfer=$tid');
        _sendStartedAt.remove(tid);
        _sendLastProgressAt.remove(tid);
        if (_activeSends > 0) _activeSends--;
        _pumpSendQueue();
      } else {
        // done 等正常状态:正常收尾应已移除,保险清理
        _sendStartedAt.remove(tid);
        _sendLastProgressAt.remove(tid);
      }
    }

    // 接收侧:发送方卡死时接收方收不到新 chunk,同样需要收敛
    for (final tid in _fileTransfers.keys.toList()) {
      final session = _fileTransfers[tid];
      if (session == null || session.direction != TransferDirection.receive) {
        continue;
      }
      if (session.status == TransferStatus.pending) {
        // writer 就绪后长时间收不到 chunk(发送方卡死/握手丢失)
        final last = _receiveLastProgressAt[tid];
        if (last != null && now.difference(last) > _sendWatchdogTimeout) {
          debugPrint('[ChatProvider] receive watchdog: no chunks, abort transfer=$tid');
          _abortReceiveTransfer(tid);
        }
      } else if (session.status == TransferStatus.transferring) {
        final last = _receiveLastProgressAt[tid];
        if (last != null && now.difference(last) > _transferStallTimeout) {
          debugPrint('[ChatProvider] receive watchdog: stalled, abort transfer=$tid');
          _abortReceiveTransfer(tid);
        }
      }
      // paused/done/failed 由正常流程处理
    }
  }

  /// 看门狗失败处理:标记失败、通知对端(两端同一 transferId)、释放并发槽并泵队列
  void _failStuckSend(String transferId, String error) {
    debugPrint('[ChatProvider] send watchdog, fail transfer=$transferId: $error');
    _sendStartedAt.remove(transferId);
    _sendLastProgressAt.remove(transferId);
    final peerId = _sendTargets[transferId]?.id ?? '';
    _updateFileSendResult(transferId, peerId, success: false, error: error);
    // 通知对端,让接收侧也收敛(两端使用同一 transferId)
    if (peerId.isNotEmpty) {
      if (_server.isPeerConnected(peerId)) {
        _server.sendFileError(peerId, transferId, error);
      } else {
        _clients[peerId]?.sendFileError(transferId, error);
      }
    }
    if (_activeSends > 0) _activeSends--;
    _pumpSendQueue();
  }

  /// 更新文件发送结果:传输状态 + 消息的发送状态
  void _updateFileSendResult(
    String transferId,
    String peerId, {
    required bool success,
    String? error,
    bool cancelled = false,
  }) {
    final session = _fileTransfers[transferId];
    if (session != null) {
      if (cancelled) {
        session.cancel();
      } else {
        session.update(
          status: success ? TransferStatus.done : TransferStatus.failed,
          progress: success ? 1.0 : session.progress,
          errorMessage: error,
        );
      }
    }
    final msgId = _transferMessageIds[transferId];
    if (msgId != null) {
      _updateSendStatus(
          peerId, msgId, success ? SendStatus.sent : SendStatus.failed);
    }
    // 发送成功后不再需要目标设备引用(避免内存泄漏;失败保留供重试)
    if (success) {
      _sendTargets.remove(transferId);
      _sendStreamFactories.remove(transferId); // 成功后无需再重开
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

  /// 处理对方发来的文件控制消息(仅剩 cancel)
  void _handleFileControl(String transferId, String action) {
    final session = _fileTransfers[transferId];
    if (session == null) {
      debugPrint('[ChatProvider] file control ignored: transfer=$transferId not found');
      return;
    }
    debugPrint('[ChatProvider] file control: $action transfer=$transferId');
    switch (action) {
      case 'file_cancel':
        session.cancel();
        // 接收侧同步清理 .part
        _cleanupReceivePart(transferId);
        break;
    }
    _syncScreenOn();
    notifyListeners();
  }

  /// 取消/失败时清理接收侧的 .part 文件与小文件缓冲
  Future<void> _cleanupReceivePart(String transferId) async {
    // 先解除背压再清理状态映射(读 _transferPeers/_receiveViaServer),
    // 否则中止/取消后对端 socket 会一直暂停,后续数据无法流动
    _resumeReceiveBackpressure(transferId);
    final writer = _receiveWriters.remove(transferId);
    final partPath = _receivePartPaths.remove(transferId);
    _receiveOffsets.remove(transferId);
    _receivePending.remove(transferId);
    _receiveWriting.remove(transferId);
    _receiveSmallBuffers.remove(transferId);
    _receiveViaServer.remove(transferId);
    _prepareStartedAt.remove(transferId);
    _receiveLastProgressAt.remove(transferId);
    if (writer != null) {
      try {
        await writer.close();
      } catch (_) {}
    }
    if (partPath != null) {
      await ReceiveDirectory.deletePartFile(partPath);
    }
  }

  /// 处理收到的文件元信息。
  /// 小文件(<= [kSmallFileThresholdBytes])走快速通道:内存缓冲直接落盘,
  /// 不建 .part;大文件异步创建 .part 文件后流式落盘。
  void _handleIncomingFileMeta(
    String transferId,
    String fileName,
    int fileSize,
    String peerId, {
    required bool viaServer,
  }) {
    final session = FileTransferSession(
      transferId: transferId,
      info: FileTransferInfo(
        fileName: fileName,
        fileSize: fileSize,
        direction: TransferDirection.receive,
        status: TransferStatus.pending,
      ),
    );
    _fileTransfers[transferId] = session;
    _transferPeers[transferId] = peerId;
    _receiveViaServer[transferId] = viaServer;
    debugPrint(
        '[ChatProvider] file_meta: transfer=$transferId name=$fileName size=$fileSize peer=$peerId viaServer=$viaServer');
    notifyListeners();

    if (fileSize <= kSmallFileThresholdBytes) {
      // 小文件快速通道:内存缓冲即刻就绪,直接回复 file_ready
      _receiveSmallBuffers[transferId] = BytesBuilder(copy: false);
      _sendFileReadyToPeer(transferId);
    } else {
      // 大文件:不立即回复 file_ready,等 .part writer 真正就绪后再回
      // (见 _prepareReceiveFile 末尾)。若立即回复,发送端会在 writer 就绪前
      // 就以网速强推 512KB 大块;chunk 只能暂存内存等待,一旦超过
      // _receivePendingLimit 就被 abort。
      _prepareStartedAt[transferId] = DateTime.now();
      _prepareReceiveFile(transferId, fileName, fileSize);
    }
    // 接收开始,同步屏幕常亮(接收期间防止熄屏挂起)
    _syncScreenOn();
  }

  /// 向发送方回复 file_ready(按接收通道选择 server/client)。
  /// 优先走接收时的那条通道;通道失效时(单连接收敛把 client 释放、
  /// 连接重建等)回退另一条通道,避免 ready 发不出去导致发送端
  /// 超时强推、接收端 pending 溢出 abort。
  void _sendFileReadyToPeer(String transferId) {
    final peerId = _transferPeers[transferId];
    if (peerId == null || peerId.isEmpty) return;
    if (_receiveViaServer[transferId] ?? false) {
      if (!_server.sendFileReady(peerId, transferId)) {
        debugPrint('[ChatProvider] ready via server FAILED, fallback client: $transferId');
        _clients[peerId]?.sendFileReady(transferId);
      } else {
        debugPrint('[ChatProvider] ready sent via server channel: $transferId');
      }
    } else {
      if (!(_clients[peerId]?.sendFileReady(transferId) ?? false)) {
        debugPrint('[ChatProvider] ready via client FAILED, fallback server: $transferId');
        _server.sendFileReady(peerId, transferId);
      } else {
        debugPrint('[ChatProvider] ready sent via client channel: $transferId');
      }
    }
  }

  /// 向发送方回发 file_error(校验失败等,按接收通道选择 server/client)
  void _sendFileErrorToPeer(
      String transferId, String peerId, String error,
      {required bool viaServer}) {
    if (peerId.isEmpty) return;
    if (viaServer) {
      _server.sendFileError(peerId, transferId, error);
    } else {
      _clients[peerId]?.sendFileError(transferId, error);
    }
  }

  /// 接收侧异常处理:发送方报错时标记失败并清理,而不是当完成;
  /// 发送方向收到 file_error(对方校验失败)时,也把本地发送标记为失败。
  void _handleReceiveFileError(String transferId, String error) {
    debugPrint('[ChatProvider] receive file error: transfer=$transferId error=$error');
    final session = _fileTransfers[transferId];
    if (session == null) return;
    if (session.direction == TransferDirection.receive) {
      _cleanupReceivePart(transferId);
      session.update(status: TransferStatus.failed, errorMessage: error);
    } else {
      // 发送方向:对方报告校验失败/接收出错,消息状态改为失败(不释放 target,支持重试)
      session.update(status: TransferStatus.failed, errorMessage: error);
      // 接收端可能已清理断点数据(如取消/失败后 .part 被删),
      // 重置 offset 让重试从头发送,避免续传拼接空洞
      session.offset = 0;
      final msgId = _transferMessageIds[transferId];
      if (msgId != null) {
        _updateSendStatus(_sendTargets[transferId]?.id ?? '', msgId, SendStatus.failed);
      }
    }
    _syncScreenOn();
    notifyListeners();
  }

  /// 创建 .part 文件并打开写句柄(异步,完成后开始落盘)
  Future<void> _prepareReceiveFile(
      String transferId, String fileName, int fileSize) async {
    try {
      final partPath =
          await ReceiveDirectory.createPartFile(transferId, fileName);

      // 打开追加写句柄
      final writer = await File(partPath).open(mode: FileMode.append);
      _receiveWriters[transferId] = writer;
      _receivePartPaths[transferId] = partPath;
      _receiveOffsets[transferId] = 0;
      // writer 就绪即开始计时(接收侧停滞看门狗:就绪后长时间无 chunk 视为发送方卡死)
      _receiveLastProgressAt[transferId] = DateTime.now();

      final session = _fileTransfers[transferId];
      if (session != null) {
        session.offset = 0;
        session.update(
          status: TransferStatus.transferring,
          progress: 0.0,
        );
        notifyListeners();
      }

      // 落盘等待期间到达的缓冲数据
      final pending = _receivePending.remove(transferId);
      if (pending != null && pending.isNotEmpty) {
        _writeReceiveChunk(transferId, pending.takeBytes());
      }
      debugPrint('[ChatProvider] part ready: $partPath');
      // 准备完成,不再需要超时诊断标记
      _prepareStartedAt.remove(transferId);
      // 接收就绪,通知发送方开始推数据
      _sendFileReadyToPeer(transferId);
    } catch (e) {
      debugPrint('[ChatProvider] prepare receive FAILED: $e');
      final session = _fileTransfers[transferId];
      if (session != null) {
        session.update(status: TransferStatus.failed, errorMessage: e.toString());
        notifyListeners();
      }
      // 回发 file_error,让发送方停止空推
      // (否则发送端继续推数据,接收端 writer 未就绪导致 pending 溢出)
      final peerId = _transferPeers[transferId] ?? '';
      final viaServer = _receiveViaServer[transferId] ?? false;
      if (peerId.isNotEmpty) {
        _sendFileErrorToPeer(transferId, peerId, '接收端准备失败: $e',
            viaServer: viaServer);
      }
      _syncScreenOn();
    }
  }

  /// 接收文件数据块:小文件直接进内存缓冲;大文件 writer 就绪则写,否则暂存等待。
  void _receiveFileChunk(String transferId, List<int> chunk) {
    final small = _receiveSmallBuffers[transferId];
    if (small != null) {
      // 小文件快速通道:累积到内存,file_done 时一次性落盘
      small.add(chunk);
      final session = _fileTransfers[transferId];
      if (session != null) {
        final total = small.length;
        session.offset = total;
        session.update(
          status: TransferStatus.transferring,
          progress: session.fileSize > 0
              ? (total / session.fileSize).clamp(0.0, 1.0)
              : 0.0,
        );
        if (_shouldNotifyTransferProgress()) notifyListeners();
      }
      _receiveLastProgressAt[transferId] = DateTime.now();
      return;
    }
    if (!_receiveWriters.containsKey(transferId)) {
      // writer 未就绪:暂存等待,但设软上限防止旧版本对端(不回 ready)大文件内存膨胀;
      // 准备超过 10s(通常意味着 ready 没能送达发送端或准备 IO 卡死)直接中止,
      // 给出明确错误而不是默默堆到 64MB 再 abort
      final pending = _receivePending[transferId] ??= BytesBuilder(copy: false);
      final started = _prepareStartedAt[transferId];
      if (started != null &&
          DateTime.now().difference(started) > const Duration(seconds: 10)) {
        debugPrint(
            '[ChatProvider] receive prepare timeout, abort transfer=$transferId '
            'pending=${pending.length}');
        _abortReceiveTransfer(transferId);
        return;
      }
      if (pending.length + chunk.length > _receivePendingLimit) {
        debugPrint(
            '[ChatProvider] receive pending overflow, abort transfer=$transferId '
            'pending=${pending.length} prepareMs=${started == null ? -1 : DateTime.now().difference(started).inMilliseconds}');
        _abortReceiveTransfer(transferId);
        return;
      }
      pending.add(chunk);
      // 背压:超过高水位暂停对端读取,避免堆积到 64MB abort
      _applyReceiveBackpressure(transferId);
      return;
    }
    _writeReceiveChunk(transferId, chunk);
  }

  /// 接收背压:暂存缓冲超过高水位时暂停对端 socket 读取,
  /// 让 TCP 窗口填满、发送方 flush 阻塞自然减速(替代堆积到 64MB 再 abort)
  void _applyReceiveBackpressure(String transferId) {
    final pending = _receivePending[transferId];
    if (pending == null || pending.length < _receivePendingHighWater) return;
    final peerId = _transferPeers[transferId];
    if (peerId == null || peerId.isEmpty) return;
    if (_receiveViaServer[transferId] ?? false) {
      _server.pausePeerRead(peerId);
    } else {
      _clients[peerId]?.pauseRead();
    }
  }

  /// 接收背压解除:恢复对端 socket 读取,数据继续流动
  void _resumeReceiveBackpressure(String transferId) {
    final peerId = _transferPeers[transferId];
    if (peerId == null || peerId.isEmpty) return;
    if (_receiveViaServer[transferId] ?? false) {
      _server.resumePeerRead(peerId);
    } else {
      _clients[peerId]?.resumeRead();
    }
  }

  /// 接收侧异常中止:清理暂存/写句柄并标记失败(如等待缓冲溢出)
  void _abortReceiveTransfer(String transferId) {
    final session = _fileTransfers[transferId];
    // 必须先取 peerId/viaServer 再清理:_cleanupReceivePart 会同步移除
    // _transferPeers/_receiveViaServer,先清理后读取会让 peerId 变成空,
    // file_error 永远发不出去,发送端继续空推、反复触发 abort
    final peerId = _transferPeers[transferId] ?? '';
    final viaServer = _receiveViaServer[transferId] ?? false;
    _cleanupReceivePart(transferId);
    if (session != null) {
      session.update(
        status: TransferStatus.failed,
        errorMessage: '接收缓冲溢出,已中止',
      );
      notifyListeners();
    }
    // 回发 file_error,让发送方停止空推并标记失败(否则发送端会继续推数据,
    // 接收端持续打印 chunk 日志且永远不落盘)
    if (peerId.isNotEmpty) {
      _sendFileErrorToPeer(transferId, peerId, '接收缓冲溢出,已中止',
          viaServer: viaServer);
    }
    _syncScreenOn();
  }

  /// 顺序写入 .part(同一 transfer 串行,防止乱序)
  void _writeReceiveChunk(String transferId, List<int> chunk) {
    if (_receiveWriting[transferId] ?? false) {
      // 写入中:暂存等待;同样受软上限保护,防止磁盘慢时暂存无界增长
      final pending = _receivePending[transferId] ??= BytesBuilder(copy: false);
      if (pending.length + chunk.length > _receivePendingLimit) {
        debugPrint(
            '[ChatProvider] receive pending overflow, abort transfer=$transferId');
        _abortReceiveTransfer(transferId);
        return;
      }
      pending.add(chunk);
      // 背压:超过高水位暂停对端读取,避免堆积到 64MB abort
      _applyReceiveBackpressure(transferId);
      return;
    }
    _receiveWriting[transferId] = true;
    _doWriteReceiveChunk(transferId, chunk);
  }

  Future<void> _doWriteReceiveChunk(String transferId, List<int> chunk) async {
    try {
      final writer = _receiveWriters[transferId];
      final session = _fileTransfers[transferId];
      if (writer != null && session != null) {
        await writer.writeFrom(chunk);
        _receiveLastProgressAt[transferId] = DateTime.now(); // 停滞看门狗
        final total = (_receiveOffsets[transferId] ?? 0) + chunk.length;
        _receiveOffsets[transferId] = total;
        session.offset = total;
        session.update(
          status: TransferStatus.transferring,
          progress: session.fileSize > 0
              ? (total / session.fileSize).clamp(0.0, 1.0)
              : 0.0,
        );
        // 进度通知节流(150ms),避免高频全量重建
        if (_shouldNotifyTransferProgress()) {
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[ChatProvider] write part FAILED: $e');
      // 写盘失败(磁盘满/IO 错误):立即中止传输并回发错误,
      // 避免后续 chunk 被丢弃、错误被延迟到 MD5 校验时误报
      final peerId = _transferPeers[transferId] ?? '';
      final viaServer = _receiveViaServer[transferId] ?? false;
      _sendFileErrorToPeer(transferId, peerId, '接收落盘失败: $e', viaServer: viaServer);
      _abortReceiveTransfer(transferId);
    } finally {
      _receiveWriting[transferId] = false;
      // 处理等待中的数据(takeBytes 会清空 BytesBuilder 并返回剩余字节)
      final pending = _receivePending[transferId];
      if (pending != null && pending.isNotEmpty) {
        _writeReceiveChunk(transferId, pending.takeBytes());
      } else {
        // 暂存已排空:解除背压,恢复对端 socket 读取
        _resumeReceiveBackpressure(transferId);
      }
    }
  }

  /// 等待该传输的写入链排空(正在写或仍有 pending 时等待),
  /// 确保 file_done 到达时所有数据都已落盘。
  Future<void> _flushReceivePending(String transferId) async {
    while ((_receiveWriting[transferId] ?? false) ||
        (_receivePending[transferId]?.isNotEmpty ?? false)) {
      await Future.delayed(const Duration(milliseconds: 5));
    }
  }

  /// 文件接收完成：小文件从内存缓冲直接落盘；大文件关闭写句柄、转正 .part。
  /// [expectedMd5] 为发送方随 file_done 携带的校验值,非空时校验,不匹配标记失败。
  Future<void> _finalizeFileReceive(String transferId, String? expectedMd5) async {
    // 先排空写入链,避免丢失尚未落盘的 pending 数据
    await _flushReceivePending(transferId);
    // 写入链已排空:解除背压,恢复对端 socket 读取
    _resumeReceiveBackpressure(transferId);
    final session = _fileTransfers[transferId];
    if (session == null) return;

    // ---- 小文件快速通道:内存缓冲直接落盘(不建 .part、不存断点索引)----
    final small = _receiveSmallBuffers.remove(transferId);
    if (small != null) {
      final peerId = _transferPeers.remove(transferId) ?? '';
      final viaServer = _receiveViaServer.remove(transferId) ?? false;
      _receiveLastProgressAt.remove(transferId);
      try {
        final bytes = small.takeBytes();
        // 校验 MD5(发送方未携带时跳过)
        if (expectedMd5 != null && expectedMd5.isNotEmpty) {
          final actual = md5Sum(bytes);
          if (actual != expectedMd5) {
            throw Exception('文件校验失败(MD5 不匹配)');
          }
        }
        final location = await ReceiveDirectory.saveReceivedFile(bytes, session.fileName);
        if (location.isEmpty) {
          throw Exception('save received file failed');
        }
        debugPrint('[ChatProvider] small file received: $location');
        _buildReceivedMessage(session, peerId, location);
        session.update(status: TransferStatus.done, progress: 1.0);
      } catch (e, st) {
        debugPrint('[ChatProvider] small file receive error: $e\n$st');
        session.update(status: TransferStatus.failed, errorMessage: e.toString());
        // 校验失败回发,让发送方消息也标记为失败
        _sendFileErrorToPeer(transferId, peerId, e.toString(), viaServer: viaServer);
      }
      notifyListeners();
      _syncScreenOn();
      return;
    }

    // ---- 大文件:.part 流式落盘后转正 ----
    final writer = _receiveWriters.remove(transferId);
    final partPath = _receivePartPaths.remove(transferId);
    final peerId = _transferPeers.remove(transferId) ?? '';
    final viaServer = _receiveViaServer.remove(transferId) ?? false;
    _receiveOffsets.remove(transferId);
    _receivePending.remove(transferId);
    _receiveWriting.remove(transferId);
    _receiveLastProgressAt.remove(transferId);
    if (writer == null || partPath == null) {
      debugPrint('[ChatProvider] finalize receive FAILED: transfer=$transferId data missing');
      return;
    }

    try {
      await writer.close();
      // C方案: 转正先行——先完成文件转正与消息入库,UI 立即显示完成;
      // MD5 校验改为后台 isolate 异步执行(见 _verifyReceivedFileAsync),
      // 不再阻塞完成路径(原实现先同步校验再转正,大文件整文件重读期间
      // 完成流程被长时间挂起,是接收端"发送完成即卡死"的根因之一)。
      final location = await ReceiveDirectory.finalizePartFile(partPath, session.fileName);
      if (location.isEmpty) {
        throw Exception('finalize part failed');
      }
      debugPrint('[ChatProvider] file received: $location');

      _buildReceivedMessage(session, peerId, location);
      session.update(status: TransferStatus.done, progress: 1.0);
      // 后台异步校验:仅真实文件路径可读(Android MediaStore 展示路径不可读时跳过);
      // 校验失败由该方法补标记 failed、回发 file_error,并尽量删除已转正文件
      if (expectedMd5 != null && expectedMd5.isNotEmpty) {
        unawaited(_verifyReceivedFileAsync(
            transferId, location, expectedMd5, session, peerId, viaServer));
      }
    } catch (e, st) {
      debugPrint('[ChatProvider] finalize receive error: $e\n$st');
      await ReceiveDirectory.deletePartFile(partPath);
      session.update(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      );
    }
    _syncScreenOn();
    notifyListeners();
  }

  /// C方案: 转正完成后在后台校验接收文件 MD5(不阻塞完成路径)。
  /// 仅对真实文件路径校验(Android MediaStore 展示路径不可读时跳过);
  /// 校验失败时补标记 failed、回发 file_error,并尽量删除已转正的文件。
  Future<void> _verifyReceivedFileAsync(
    String transferId,
    String location,
    String expectedMd5,
    FileTransferSession session,
    String peerId,
    bool viaServer,
  ) async {
    try {
      final file = File(location);
      if (!await file.exists()) {
        debugPrint('[ChatProvider] MD5 verify skipped (path not readable): $location');
        return;
      }
      final actual = await md5SumFileSegment(location);
      if (actual == expectedMd5) return;
      debugPrint('[ChatProvider] MD5 mismatch after finalize: $location');
      // 尽量删除已转正文件(桌面真实路径可删;不可删时仅标记失败)
      try {
        await file.delete();
      } catch (_) {}
      session.update(
        status: TransferStatus.failed,
        errorMessage: '文件校验失败(MD5 不匹配)',
      );
      // 校验失败回发,让发送方消息也标记为失败
      _sendFileErrorToPeer(transferId, peerId, '文件校验失败(MD5 不匹配)',
          viaServer: viaServer);
      notifyListeners();
    } catch (e) {
      debugPrint('[ChatProvider] MD5 verify error: $e');
    }
  }

  /// 为接收完成的文件生成消息记录
  void _buildReceivedMessage(FileTransferSession session, String peerId, String location) {
    final msg = ChatMessage(
      id: const Uuid().v4(),
      senderId: peerId,
      senderName: '',
      type: MessageType.file,
      content: _encodeFileContent(session.fileName, session.fileSize,
          session.transferId, path: location),
      timestamp: DateTime.now(),
    );
    _saveMessage(msg, peerId);
    _messageController.add(msg);
  }

  /// 计算字节序列的 MD5(小文件缓冲落盘校验兜底)
  static String md5Sum(List<int> bytes) => md5.convert(bytes).toString();

  /// 在后台 isolate 中流式计算文件 MD5。
  /// 纯 Dart MD5 在主 isolate 上逐块计算会占满事件循环,大文件接收时
  /// 导致 UI 卡死(Windows 发大文件到 Linux 卡死根因),故改为落盘完成后
  /// 一次性在后台 isolate 计算,期间主 isolate 只负责 IO 与 UI。
  static Future<String> md5SumFileSegment(String path) {
    return Isolate.run(() async {
      final file = File(path);
      final raf = await file.open();
      try {
        final acc = Md5Accumulator();
        final chunkSize = 1024 * 1024;
        while (true) {
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;
          acc.add(chunk);
        }
        return acc.close();
      } finally {
        await raf.close();
      }
    });
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
    _sendWatchdogTimer?.cancel();
    // 兜底熄灭屏幕常亮(传输未正常结束时防止屏幕一直亮着)
    if (_screenOnHeld) {
      _screenOnHeld = false;
      ScreenKeepOn.release();
    }
    stopServer();
    for (final client in _clients.values) {
      client.dispose();
    }
    _clients.clear();
    // 关闭所有未完成的接收写句柄
    for (final writer in _receiveWriters.values) {
      try {
        writer.close();
      } catch (_) {}
    }
    _receiveWriters.clear();
    _receivePartPaths.clear();
    _receiveOffsets.clear();
    _receivePending.clear();
    _receiveWriting.clear();
    _receiveSmallBuffers.clear();
    _receiveViaServer.clear();
    _receiveLastProgressAt.clear();
    _sendLastProgressAt.clear();
    _sendStreams.clear();
    _messageController.close();
    super.dispose();
  }
}