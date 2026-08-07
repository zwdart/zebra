import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lan_device.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';
import '../widgets/file_transfer_tile.dart';
import '../services/receive_directory.dart';
import '../services/native_file_stream.dart';
import '../../../widgets/custom_title_bar.dart';
import '../../../widgets/window_drag_region.dart';
import '../../../l10n/app_localizations.dart';

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
  // ---- 多选模式状态 ----
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  // ---- 拖拽发送状态(桌面端拖文件进聊天窗口直接发送)----
  bool _isDragOver = false;

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
            AppLocalizations.of(context).connecting,
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
            AppLocalizations.of(context).waitingForPeer,
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
          Text(
            AppLocalizations.of(context).connected,
            style: TextStyle(fontSize: 10, color: Colors.green),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 10, color: colorScheme.error),
        const SizedBox(width: 3),
        Text(
          AppLocalizations.of(context).disconnected,
          style: TextStyle(fontSize: 10, color: colorScheme.error),
        ),
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
    final loc = AppLocalizations.of(context);
    // 打开文件选择器前先提示,避免 pickFiles 内部复制大文件期间看似无反应
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(loc.pickingFiles),
          duration: const Duration(seconds: 4),
        ),
      );

    final chatProvider = context.read<ChatProvider>();
    final peer = _makePeerDevice();
    var sent = 0;

    if (NativeFileStream.isSupported) {
      // Android/iOS:原生直读流(SAF/UIDocumentPicker),零复制、选完即传;
      // 可重开流工厂支持断点续传(重试时按已传 offset 重新定位)
      // 仅支持单文件传输:原生选择器已限制单选,这里再兜底只取第一个
      final picked = await NativeFileStream.pickFiles();
      if (picked.isEmpty || !mounted) return;
      final f = picked.first;
      // 无法确定大小的文件跳过(本地 provider 一般都能返回)
      if (f.size >= 0) {
        chatProvider.sendFile(
          target: peer,
          fileName: f.name,
          fileSize: f.size,
          readStreamFactory: (offset) =>
              NativeFileStream.openRead(f.uri, offset: offset),
        );
        sent++;
      }
    } else {
      // 桌面:file_picker 路径方案(选中即得真实路径,无复制等待);
      // 仅支持单文件传输:allowMultiple=false
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withReadStream: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      // 选完后立即反馈"正在准备传输",大文件此时可能仍在复制/准备
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(loc.preparingFiles(1)),
            duration: const Duration(seconds: 4),
          ),
        );

      final file = result.files.first;
      // path 可能为 null(readStream 模式);两者任一可用即可发送
      if (file.path != null || file.readStream != null) {
        chatProvider.sendFile(
          target: peer,
          filePath: file.path,
          fileName: file.name,
          fileSize: file.size,
          readStream: file.readStream,
        );
        sent++;
      }
    }
    if (sent == 0) return;

    setState(() {
      _messages = chatProvider.getMessages(widget.peerId);
    });
    _scrollToBottom();
  }

  /// 处理拖拽进入的文件列表(桌面端拖文件进聊天窗口直接发送)。
  /// 逐文件发送到当前聊天对象;跳过无法读取的路径。
  Future<void> _handleDroppedFiles(List<DropItem> files) async {
    if (files.isEmpty || !mounted) return;
    final chatProvider = context.read<ChatProvider>();
    final peer = _makePeerDevice();
    var sent = 0;
    for (final f in files) {
      final path = f.path;
      if (path.isEmpty) continue;
      // 目录不支持直接发送,跳过
      if (await FileSystemEntity.isDirectory(path)) continue;
      final size = await f.length();
      chatProvider.sendFile(
        target: peer,
        filePath: path,
        fileName: f.name,
        fileSize: size,
      );
      sent++;
    }
    if (sent == 0) return;

    setState(() {
      _messages = chatProvider.getMessages(widget.peerId);
    });
    _scrollToBottom();
  }

  /// 打开接收文件目录(右上角菜单"文件夹")。
  /// 目录不存在时 ReceiveDirectory 会先创建再打开;失败时提示用户。
  Future<void> _openReceivedFolder() async {
    final loc = AppLocalizations.of(context);
    final ok = await ReceiveDirectory.openReceivedFolder();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.openFolderFailed)),
      );
    }
  }

  // ==================== 多选模式 ====================

  /// 长按菜单选择"多选"后进入多选模式,并选中当前消息
  void _enterSelectionMode(String messageId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
      _selectedIds.add(messageId);
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String messageId) {
    setState(() {
      if (!_selectedIds.add(messageId)) {
        _selectedIds.remove(messageId);
      }
    });
  }

  /// 删除选中的消息(二次确认)
  Future<void> _confirmDeleteSelected() async {
    final loc = AppLocalizations.of(context);
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.deleteMessages),
        content: Text(loc.confirmDeleteMessagesValue(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ids = _selectedIds.toList();
    _chatProvider.deleteMessages(widget.peerId, ids);
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
      _messages = _chatProvider.getMessages(widget.peerId);
    });
  }

  /// 合并分享:文字消息合并为一段文本,文件消息附带真实路径一起分享
  Future<void> _mergeShareSelected() async {
    final loc = AppLocalizations.of(context);
    final selected = _messages.where((m) => _selectedIds.contains(m.id)).toList();
    if (selected.isEmpty) return;

    final textParts = <String>[];
    final filePaths = <String>[];
    for (final msg in selected) {
      if (msg.type == MessageType.text) {
        textParts.add(msg.content);
      } else if (msg.type == MessageType.file) {
        final path = _filePathOf(msg);
        if (path != null && File(path).existsSync()) {
          filePaths.add(path);
        }
      }
    }

    // 文件分享走 shareXFiles,文本作为附带说明;纯文本直接合并分享
    if (filePaths.isNotEmpty) {
      await Share.shareXFiles(
        filePaths.map((p) => XFile(p)).toList(),
        text: textParts.isEmpty ? null : textParts.join('\n\n'),
      );
    } else if (textParts.isNotEmpty) {
      await Share.share(textParts.join('\n\n'));
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.fileNotShareable)),
      );
    }
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 从文件消息的 JSON 内容中解析本地文件路径
  String? _filePathOf(ChatMessage msg) {
    try {
      final map = jsonDecode(msg.content) as Map<String, dynamic>;
      return map['path'] as String?;
    } catch (_) {
      return null;
    }
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
        title: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(ctx).chatDetails),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailSectionTitle(ctx, AppLocalizations.of(ctx).peerDevice),
            _infoRow(ctx, Icons.person, AppLocalizations.of(ctx).deviceName, widget.peerName),
            _infoRow(ctx, Icons.tag, 'ID', widget.peerId),
            _infoRow(ctx, Icons.lan, AppLocalizations.of(ctx).ipAddress, widget.peerIp),
            _infoRow(ctx, Icons.settings_ethernet, AppLocalizations.of(ctx).portNumber, '${widget.peerPort}'),
            const Divider(height: 24),
            _detailSectionTitle(ctx, AppLocalizations.of(ctx).localDevice),
            _infoRow(ctx, Icons.person, AppLocalizations.of(ctx).deviceName, chatProvider.selfName),
            _infoRow(ctx, Icons.tag, 'ID', chatProvider.selfId),
            _infoRow(ctx, Icons.lan, AppLocalizations.of(ctx).ipAddress, localIp),
            _infoRow(
              ctx,
              Icons.settings_ethernet,
              AppLocalizations.of(ctx).portNumber,
              '${chatProvider.tcpPort}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).close),
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

  /// 构建标题栏标题(多选模式显示已选数量,普通模式显示头像+用户名+IP+连接状态)
  Widget _buildTitleWidget(ColorScheme colorScheme) {
    if (_selectionMode) {
      return Text(
        AppLocalizations.of(context).selectedCountValue(_selectedIds.length),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Row(
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
    );
  }

  /// 构建标题栏操作按钮(多选模式:合并分享/删除;普通模式:更多菜单)
  List<Widget> _buildAppBarActions(ColorScheme colorScheme) {
    if (_selectionMode) {
      return [
        // 合并分享:文字合并为一段文本,文件附带真实路径
        TextButton.icon(
          onPressed: _selectedIds.isEmpty ? null : () => _mergeShareSelected(),
          icon: const Icon(Icons.ios_share, size: 18),
          label: Text(AppLocalizations.of(context).mergeShare),
        ),
        TextButton.icon(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => _confirmDeleteSelected(),
          icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
          label: Text(
            AppLocalizations.of(context).delete,
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      ];
    }
    return [
      PopupMenuButton<String>(
        tooltip: AppLocalizations.of(context).more,
        onSelected: (value) {
          switch (value) {
            case 'details':
              _showDetailsDialog();
            case 'folder':
              _openReceivedFolder();
            case 'reconnect':
              _ensureConnected();
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'details',
            child: ListTile(
              leading: const Icon(Icons.info_outline, size: 18),
              title: Text(
                AppLocalizations.of(ctx).viewDetail,
                style: const TextStyle(fontSize: 14),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'folder',
            child: ListTile(
              leading: const Icon(Icons.folder_open, size: 18),
              title: Text(
                AppLocalizations.of(ctx).openFolder,
                style: const TextStyle(fontSize: 14),
              ),
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
                  _isConnecting
                      ? AppLocalizations.of(ctx).connecting
                      : AppLocalizations.of(ctx).reconnect,
                  style: const TextStyle(fontSize: 14),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomTitleBar.isDesktop
          ? null
          : WindowDragRegion(
              child: AppBar(
                // 压缩标题与返回按钮的默认间距,给长用户名留更多空间
                titleSpacing: _selectionMode ? 4 : 8,
                // 多选模式下:leading 变为关闭按钮,标题变为已选数量
                leading: _selectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: AppLocalizations.of(context).cancel,
                        onPressed: _exitSelectionMode,
                      )
                    : null,
                title: _buildTitleWidget(colorScheme),
                actions: _buildAppBarActions(colorScheme),
              ),
            ),
      body: Column(
        children: [
          // 桌面端:自定义标题栏(含最小化/最大化/关闭按钮),支持返回
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              titleWidget: _buildTitleWidget(colorScheme),
              showBackButton: true,
              onBack: () => Navigator.of(context).maybePop(),
              actions: _buildAppBarActions(colorScheme),
            ),
          Expanded(
            child: DropTarget(
        onDragEntered: (_) {
          if (mounted) setState(() => _isDragOver = true);
        },
        onDragExited: (_) {
          if (mounted) setState(() => _isDragOver = false);
        },
        onDragDone: (details) {
          if (mounted) setState(() => _isDragOver = false);
          _handleDroppedFiles(details.files);
        },
        child: Stack(
          children: [
            Column(
              children: [
          // 重连中提示条(发送/文件传输前自动重连时显示)
          Consumer<ChatProvider>(
            builder: (ctx, provider, _) {
              if (!provider.isReconnecting) return const SizedBox.shrink();
              final cs = Theme.of(ctx).colorScheme;
              return Container(
                width: double.infinity,
                color: cs.tertiaryContainer.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(ctx).connecting,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // 当前文件传输列表(批量/取消,仅当前会话的传输)
          Consumer<ChatProvider>(
            builder: (ctx, provider, _) {
              final active = provider
                  .transfersForPeer(widget.peerId)
                  .where((t) {
                    final s = t.status;
                    return s == TransferStatus.pending ||
                        s == TransferStatus.transferring;
                  })
                  .toList();
              if (active.isEmpty) return const SizedBox.shrink();
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: active.length,
                  itemBuilder: (ctx, i) {
                    final s = active[i];
                    return FileTransferTile(
                      session: s,
                      onCancel: () => provider.cancelTransfer(s.transferId),
                    );
                  },
                ),
              );
            },
          ),
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
                          AppLocalizations.of(context).startChat,
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
                      return MessageBubble(
                        message: msg,
                        peerId: widget.peerId,
                        selectionMode: _selectionMode,
                        isSelected: _selectedIds.contains(msg.id),
                        onToggleSelect: () => _toggleSelect(msg.id),
                        onMultiSelect: () => _enterSelectionMode(msg.id),
                        onDelete: () {
                          _chatProvider.deleteMessages(widget.peerId, [msg.id]);
                          setState(() {
                            _messages =
                                _chatProvider.getMessages(widget.peerId);
                          });
                        },
                      );
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
                  tooltip: AppLocalizations.of(context).sendFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _inputFocusNode,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).messageHint,
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
                  tooltip: AppLocalizations.of(context).send,
                ),
              ],
            ),
          ),
              ],
            ),
            // 拖拽悬停提示层:提示松开即可发送文件
            if (_isDragOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_upload_outlined,
                              color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context).dragFilesHere),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
      ],
      ),
    );
  }
}
