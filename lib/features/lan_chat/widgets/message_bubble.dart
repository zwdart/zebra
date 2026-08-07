import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../services/receive_directory.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/relative_time.dart';

/// 消息气泡组件
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String peerId;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onMultiSelect;
  final VoidCallback? onDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.peerId,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onMultiSelect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (selectionMode && !isMe) _buildSelectCheck(context),
          if (!isMe) _buildAvatar(context),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.65,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    border: isSelected
                        ? Border.all(color: colorScheme.primary, width: 2)
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: GestureDetector(
                    // 长按(移动端)与右键(桌面端)呼出菜单
                    onLongPressStart: selectionMode
                        ? null
                        : (d) => _showMessageMenu(context, d.globalPosition),
                    onSecondaryTapDown: selectionMode
                        ? null
                        : (d) => _showMessageMenu(context, d.globalPosition),
                    // 多选模式下点击切换选中
                    onTap: selectionMode ? () => onToggleSelect?.call() : null,
                    child: _buildContent(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMe && message.sendStatus != SendStatus.sent)
                        _buildSendStatus(context),
                      if (isMe && message.sendStatus != SendStatus.sent)
                        const SizedBox(width: 4),
                      Text(
                        _formatTime(context, message.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
          if (isMe) _buildAvatar(context),
          if (selectionMode && isMe) _buildSelectCheck(context),
        ],
      ),
    );
  }

  /// 多选模式下显示的圆形勾选框
  Widget _buildSelectCheck(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 6, bottom: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? colorScheme.primary : Colors.transparent,
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: 1.5,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check, size: 14, color: colorScheme.onPrimary)
            : null,
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        message.senderName.isNotEmpty
            ? message.senderName[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildSendStatus(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (message.sendStatus) {
      case SendStatus.sending:
        return SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: colorScheme.outline),
        );
      case SendStatus.failed:
        return Icon(Icons.error_outline, size: 12, color: colorScheme.error);
      case SendStatus.sent:
        return const SizedBox.shrink();
    }
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.text:
        return Text(
          message.content,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
      case MessageType.file:
        return _buildFileContent(context);
      case MessageType.system:
        return Text(
          message.content,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
    }
  }

  Widget _buildFileContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 解析文件信息（content 为 JSON）
    final loc = AppLocalizations.of(context);
    String fileName = loc.fileDefaultName;
    String fileSize = '';
    String? path;
    String? transferId;
    try {
      final map = jsonDecode(message.content) as Map<String, dynamic>;
      fileName = map['fileName'] as String? ?? loc.fileDefaultName;
      final size = map['fileSize'] as int? ?? 0;
      fileSize = FileTransferInfo.formatSize(size);
      path = map['path'] as String?;
      transferId = map['transferId'] as String?;
    } catch (_) {}

    // 传输中的会话:watch 监听进度变化,实时刷新速度/剩余时间
    final session = (transferId != null && transferId.isNotEmpty)
        ? context.watch<ChatProvider>().getFileTransfer(transferId)
        : null;
    return InkWell(
      // 多选模式下禁用文件点击,让外层 GestureDetector 处理选中
      onTap: (selectionMode || path == null)
          ? null
          : () => _onFileTap(context, path!),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (session != null &&
                      (session.status == TransferStatus.pending ||
                          session.status == TransferStatus.transferring)) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: session.progress,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(session.progress * 100).toStringAsFixed(0)}% '
                      '${FileTransferInfo.formatSize(session.transferredBytes)} / $fileSize',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.progressLine(
                        remainingLabel: loc.remainingTimeLabel,
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (fileSize.isNotEmpty)
                    Text(
                      path == null ? fileSize : '$fileSize ${loc.viewFolderHint}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (message.isMe && message.sendStatus == SendStatus.failed &&
                transferId != null && transferId.isNotEmpty)
              IconButton(
                icon: Icon(Icons.refresh, size: 16, color: colorScheme.error),
                tooltip: loc.retry,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () =>
                    context.read<ChatProvider>().retryTransfer(transferId!),
              ),
            if (message.isMe && message.sendStatus == SendStatus.sent)
              Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  /// 点击文件:打开所在目录,而不是直接打开文件
  void _onFileTap(BuildContext context, String path) {
    final loc = AppLocalizations.of(context);
    if (Platform.isAndroid && !path.startsWith('/')) {
      // Android 上通过 MediaStore 保存时,path 是展示路径(如 Download/zebra/x.pdf),
      // 不是真实路径,直接打开系统"下载"目录
      ReceiveDirectory.openDownloadsFolder().then((ok) {
        if (!ok && context.mounted) {
          _showErrorDialog(context, loc.cannotOpenDownloads, loc.downloadsUnavailable);
        }
      });
      return;
    }
    // 其余情况(桌面端、Android 降级路径、发送方本地文件):打开所在目录
    _openContainingDirectory(context, path);
  }

  /// 长按/右键消息时在当前指针位置弹出操作菜单
  Future<void> _showMessageMenu(BuildContext context, Offset position) async {
    // 系统消息不提供菜单
    if (message.type == MessageType.system) return;

    // 移动端弹出菜单前先收起输入法:showMenu 出栈后会恢复输入框焦点,
    // 导致取消/选择菜单后键盘自动弹出;桌面端无软键盘,保持原样
    if (Platform.isAndroid || Platform.isIOS) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    final actions = <PopupMenuEntry<String>>[];
    final loc = AppLocalizations.of(context);
    if (message.type == MessageType.text) {
      actions
        ..add(PopupMenuItem(value: 'detail', child: Text(loc.viewDetail)))
        ..add(PopupMenuItem(value: 'copy', child: Text(loc.copy)))
        ..add(PopupMenuItem(value: 'share', child: Text(loc.share)));
    } else if (message.type == MessageType.file) {
      actions
        ..add(PopupMenuItem(value: 'folder', child: Text(loc.openFolder)))
        ..add(PopupMenuItem(value: 'copyPath', child: Text(loc.copyPath)))
        ..add(PopupMenuItem(value: 'share', child: Text(loc.share)));
    }
    // 多选 / 删除(所有非系统消息通用)
    actions
      ..add(PopupMenuItem(value: 'multiSelect', child: Text(loc.multiSelect)))
      ..add(PopupMenuItem(value: 'delete', child: Text(loc.delete)));

    final screenSize = MediaQuery.of(context).size;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        screenSize.width - position.dx,
        screenSize.height - position.dy,
      ),
      items: actions,
    );
    if (!context.mounted) return;
    switch (action) {
      case 'detail':
        _showTextDetail(context);
        break;
      case 'copy':
        await _copyMessage(context);
        break;
      case 'share':
        await _shareMessage(context);
        break;
      case 'folder':
        _openFileFolder(context);
        break;
      case 'copyPath':
        await _copyFilePath(context);
        break;
      case 'multiSelect':
        onMultiSelect?.call();
        break;
      case 'delete':
        await _confirmDelete(context);
        break;
    }
  }

  /// 删除消息二次确认,确认后回调删除
  Future<void> _confirmDelete(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.deleteMessages),
        content: Text(loc.confirmDeleteMessage),
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
    if (confirmed == true) onDelete?.call();
  }

  /// 文字消息:弹窗查看完整内容(可选中复制)
  void _showTextDetail(BuildContext context) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.messageDetail),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
          child: SingleChildScrollView(
            child: SelectableText(
              message.content,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.close),
          ),
        ],
      ),
    );
  }

  /// 复制消息内容(文字直接复制;文件复制文件名)
  Future<void> _copyMessage(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final text = message.type == MessageType.text
        ? message.content
        : (_fileInfo(fallbackName: loc.fileDefaultName)?.fileName ?? message.content);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.copied)),
    );
  }

  /// 复制文件消息的本地路径到剪贴板
  Future<void> _copyFilePath(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final path = _fileInfo()?.filePath;
    if (path == null || path.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.fileInfoMissing)),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.pathCopied)),
    );
  }

  /// 分享消息:文字直接分享文本,文件分享真实文件路径
  Future<void> _shareMessage(BuildContext context) async {
    if (message.type == MessageType.text) {
      await Share.share(message.content);
      return;
    }
    final loc = AppLocalizations.of(context);
    final path = _fileInfo()?.filePath;
    if (path == null || !File(path).existsSync()) {
      if (!context.mounted) return;
      // Android 上 MediaStore 展示路径不是真实路径,文件实际在系统"下载"目录
      if (Platform.isAndroid) {
        ReceiveDirectory.openDownloadsFolder();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.fileNotShareable)),
      );
      return;
    }
    await Share.shareXFiles([XFile(path)]);
  }

  /// 打开文件所在文件夹(复用点击文件的逻辑)
  void _openFileFolder(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final path = _fileInfo()?.filePath;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.fileInfoMissing)),
      );
      return;
    }
    _onFileTap(context, path);
  }

  /// 从文件消息的 JSON 内容中解析文件信息
  FileTransferInfo? _fileInfo({String fallbackName = '文件'}) {
    try {
      final map = jsonDecode(message.content) as Map<String, dynamic>;
      return FileTransferInfo(
        fileName: map['fileName'] as String? ?? fallbackName,
        fileSize: map['fileSize'] as int? ?? 0,
        filePath: map['path'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 打开文件所在目录
  Future<void> _openContainingDirectory(BuildContext context, String path) async {
    final loc = AppLocalizations.of(context);
    final dir = p.dirname(path);
    try {
      final ok = await launchUrl(Uri.directory(dir));
      if (!ok && context.mounted) {
        _showErrorDialog(context, loc.cannotOpenFolder, loc.openFolderFailed);
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, loc.openFolderFailed, '$e');
      }
    }
  }

  /// 显示居中的错误信息弹框:不占满屏幕,内容可滚动查看,带关闭按钮
  void _showErrorDialog(BuildContext context, String title, String message) {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 320),
          child: SingleChildScrollView(
            child: SelectableText(
              message,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.close),
          ),
        ],
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dt) {
    return RelativeTime.messageTime(AppLocalizations.of(context), dt);
  }
}