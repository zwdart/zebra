import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/lan_device.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';
import '../../../widgets/window_drag_region.dart';

/// 聊天界面（私聊）
class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String peerIp;
  final int peerPort;

  const ChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerIp,
    this.peerPort = 19423,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final ChatProvider _chatProvider;
  late List<ChatMessage> _messages;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isWaiting = false; // 连接失败,等待对方上线并自动重试
  Timer? _retryTimer;
  final FocusNode _inputFocusNode = FocusNode();
  StreamSubscription<ChatMessage>? _messageSub;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _messages = _chatProvider.getMessages(widget.peerId);
    debugPrint(
      '[ChatScreen] init: peerId=${widget.peerId} peerIp=${widget.peerIp} peerPort=${widget.peerPort} history=${_messages.length}',
    );
    _chatProvider.markRead(widget.peerId);
    _checkConnection();
    _chatProvider.addListener(_onProviderChanged);
    _messageSub = _chatProvider.onMessageReceived.listen((msg) {
      debugPrint(
        '[ChatScreen] stream msg: senderId=${msg.senderId} peerId=${widget.peerId} type=${msg.type.name}',
      );
      if (msg.senderId != widget.peerId) {
        // 收到但被过滤的消息：说明 senderId 与当前 peerId 对不上（设备 ID 不一致/路由错位）
        debugPrint(
          '[ChatScreen] !!! message FILTERED OUT: senderId=${msg.senderId} != peerId=${widget.peerId} content=${msg.content}',
        );
        return;
      }
      if (mounted) {
        setState(() {
          _messages = _chatProvider.getMessages(widget.peerId);
        });
        _scrollToBottom();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      // 进入聊天页自动发起连接:未连接时先显示"正在连接中",
      // 失败后进入"等待对方连接中"并自动重试
      if (!_isConnected) _ensureConnected();
    });
  }

  @override
  void dispose() {
    _chatProvider.removeListener(_onProviderChanged);
    _messageSub?.cancel();
    _stopAutoRetry();
    _textController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _checkConnection() {
    setState(() {
      _isConnected = _chatProvider.isConnectedTo(widget.peerId);
      _isConnecting = false;
    });
  }

  String _lastMessagesSig = '';

  /// 连接状态/消息变化时同步 UI（server 通道建立/断开、发送状态流转等都会 notifyListeners）
  void _onProviderChanged() {
    if (!mounted) return;
    final connected = _chatProvider.isConnectedTo(widget.peerId);
    final msgs = _chatProvider.getMessages(widget.peerId);
    final last = msgs.isEmpty ? null : msgs.last;
    // 消息数量、最后一条消息 ID 与发送状态变化时才刷新(避免文件传输进度频繁重建)
    final sig = last == null
        ? '0'
        : '${msgs.length}:${last.id}:${last.sendStatus.name}';
    if (connected == _isConnected && sig == _lastMessagesSig) return;
    _lastMessagesSig = sig;
    setState(() {
      _isConnected = connected;
      _isWaiting = !connected;
      _messages = msgs;
    });
    _scrollToBottom();
    if (connected) {
      _stopAutoRetry();
    } else if (!_isConnecting) {
      _startAutoRetry();
    }
  }

  Future<void> _ensureConnected() async {
    if (_isConnected) {
      _stopAutoRetry();
      return;
    }
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _isWaiting = false;
    });
    final chatProvider = context.read<ChatProvider>();
    final ok = await chatProvider.connectToDevice(_makePeerDevice());
    debugPrint('[ChatScreen] ensureConnected result=$ok');
    if (mounted) {
      setState(() {
        _isConnected = ok;
        _isConnecting = false;
        _isWaiting = !ok;
      });
      if (ok) {
        _stopAutoRetry();
      } else {
        // 对方服务器当前不可达(应用未开启/已离线):
        // 显示"等待对方连接中"并周期性自动重试,对方上线后即可自动连上
        _startAutoRetry();
      }
    }
  }

  /// 未连接时周期性自动重试连接
  void _startAutoRetry() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _isConnected || _isConnecting) return;
      _ensureConnected();
    });
  }

  void _stopAutoRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // 列表是 reverse:true,offset 0 才是底部(最新消息),
      // maxScrollExtent 反而是最旧消息的位置
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildConnectionStatus(ColorScheme colorScheme) {
    if (_isConnecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '连接中...',
            style: TextStyle(fontSize: 10, color: colorScheme.outline),
          ),
        ],
      );
    }
    if (_isWaiting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '等待对方连接中...',
            style: TextStyle(fontSize: 10, color: colorScheme.primary),
          ),
        ],
      );
    }
    if (_isConnected) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 10, color: Colors.green),
          const SizedBox(width: 3),
          Text('已连接', style: TextStyle(fontSize: 10, color: Colors.green)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 10, color: colorScheme.error),
        const SizedBox(width: 3),
        Text('未连接', style: TextStyle(fontSize: 10, color: colorScheme.error)),
      ],
    );
  }

  LanDevice _makePeerDevice() {
    return LanDevice(
      id: widget.peerId,
      name: widget.peerName,
      ip: widget.peerIp,
      port: widget.peerPort,
    );
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final chatProvider = context.read<ChatProvider>();
    chatProvider.sendTextMessage(_makePeerDevice(), text);
    _textController.clear();
    // 发送后重新聚焦输入框,避免桌面端发送一次后焦点丢失
    _inputFocusNode.requestFocus();

    setState(() {
      _messages = chatProvider.getMessages(widget.peerId);
    });
    _scrollToBottom();

    // 如果未连接，尝试连接
    if (!_isConnected && !_isConnecting) {
      _ensureConnected();
    }
  }

  Future<void> _pickAndSendFile() async {
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null || !mounted) return;

    final chatProvider = context.read<ChatProvider>();
    chatProvider.sendFile(
      target: _makePeerDevice(),
      filePath: file.path!,
      fileName: file.name,
      fileSize: file.size,
    );

    setState(() {
      _messages = chatProvider.getMessages(widget.peerId);
    });
    _scrollToBottom();
  }

  /// 获取本机局域网 IPv4 地址
  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        if (iface.name.startsWith('lo') ||
            iface.name.startsWith('docker') ||
            iface.name.startsWith('veth')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// 查看详情:展示当前对话双方的详细信息
  Future<void> _showDetailsDialog() async {
    final chatProvider = context.read<ChatProvider>();
    final localIp = await _getLocalIp();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, size: 20),
            SizedBox(width: 8),
            Text('对话详情'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailSectionTitle(ctx, '对方设备'),
            _infoRow(ctx, Icons.person, '设备名', widget.peerName),
            _infoRow(ctx, Icons.tag, '设备 ID', widget.peerId),
            _infoRow(ctx, Icons.lan, 'IP 地址', widget.peerIp),
            _infoRow(ctx, Icons.settings_ethernet, '端口号', '${widget.peerPort}'),
            const Divider(height: 24),
            _detailSectionTitle(ctx, '本机'),
            _infoRow(ctx, Icons.person, '设备名', chatProvider.selfName),
            _infoRow(ctx, Icons.tag, '设备 ID', chatProvider.selfId),
            _infoRow(ctx, Icons.lan, 'IP 地址', localIp),
            _infoRow(
              ctx,
              Icons.settings_ethernet,
              '端口号',
              '${chatProvider.tcpPort}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailSectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('$label：', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WindowDragRegion(
        child: AppBar(
          // 压缩标题与返回按钮的默认间距,给长用户名留更多空间
          titleSpacing: 8,
          title: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  widget.peerName.isNotEmpty
                      ? widget.peerName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 用户名过长时省略号截断,避免挤占右上角按钮区域
                    Text(
                      widget.peerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.peerIp,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildConnectionStatus(colorScheme),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                switch (value) {
                  case 'details':
                    _showDetailsDialog();
                  case 'file':
                    _pickAndSendFile();
                  case 'reconnect':
                    _ensureConnected();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'details',
                  child: ListTile(
                    leading: Icon(Icons.info_outline, size: 18),
                    title: Text('查看详情', style: TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'file',
                  child: ListTile(
                    leading: Icon(Icons.attach_file, size: 18),
                    title: Text('发送文件', style: TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!_isConnected)
                  PopupMenuItem(
                    value: 'reconnect',
                    enabled: !_isConnecting,
                    child: ListTile(
                      leading: Icon(Icons.wifi_off, size: 18),
                      title: Text(
                        _isConnecting ? '正在连接...' : '重新连接',
                        style: const TextStyle(fontSize: 14),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat,
                          size: 48,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '开始聊天吧',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    reverse: true,
                    itemBuilder: (ctx, i) {
                      final msg = _messages[_messages.length - 1 - i];
                      return MessageBubble(message: msg, peerId: widget.peerId);
                    },
                  ),
          ),

          // 输入区域
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _pickAndSendFile,
                  tooltip: '发送文件',
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _inputFocusNode,
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    maxLines: 4,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  tooltip: '发送',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
