import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../services/receive_directory.dart';

/// 消息气泡组件
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String peerId;

  const MessageBubble({
    super.key,
    required this.message,
    required this.peerId,
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
                    onLongPressStart: (d) =>
                        _showMessageMenu(context, d.globalPosition),
                    onSecondaryTapDown: (d) =>
                        _showMessageMenu(context, d.globalPosition),
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
                        _formatTime(message.timestamp),
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
        ],
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
    String fileName = '文件';
    String fileSize = '';
    String? path;
    try {
      final map = jsonDecode(message.content) as Map<String, dynamic>;
      fileName = map['fileName'] as String? ?? '文件';
      final size = map['fileSize'] as int? ?? 0;
      fileSize = _formatSize(size);
      path = map['path'] as String?;
    } catch (_) {}

    return InkWell(
      onTap: path == null ? null : () => _onFileTap(context, path!),
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
                  if (fileSize.isNotEmpty)
                    Text(
                      path == null ? fileSize : '$fileSize 点击查看目录',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
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
    if (Platform.isAndroid && !path.startsWith('/')) {
      // Android 上通过 MediaStore 保存时,path 是展示路径(如 Download/zebra/x.pdf),
      // 不是真实路径,直接打开系统"下载"目录
      ReceiveDirectory.openDownloadsFolder().then((ok) {
        if (!ok && context.mounted) {
          _showErrorDialog(context, '无法打开下载目录', '系统文件管理器不可用,请手动打开"下载"目录查看文件。');
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

    final actions = <PopupMenuEntry<String>>[];
    if (message.type == MessageType.text) {
      actions
        ..add(const PopupMenuItem(value: 'detail', child: Text('查看详情')))
        ..add(const PopupMenuItem(value: 'copy', child: Text('复制')))
        ..add(const PopupMenuItem(value: 'share', child: Text('分享')));
    } else if (message.type == MessageType.file) {
      actions
        ..add(const PopupMenuItem(value: 'folder', child: Text('打开文件夹')))
        ..add(const PopupMenuItem(value: 'share', child: Text('分享')));
    }

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
    }
  }

  /// 文字消息:弹窗查看完整内容(可选中复制)
  void _showTextDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('消息详情'),
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
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 复制消息内容(文字直接复制;文件复制文件名)
  Future<void> _copyMessage(BuildContext context) async {
    final text = message.type == MessageType.text
        ? message.content
        : (_fileInfo()?.fileName ?? message.content);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  /// 分享消息:文字直接分享文本,文件分享真实文件路径
  Future<void> _shareMessage(BuildContext context) async {
    if (message.type == MessageType.text) {
      await Share.share(message.content);
      return;
    }
    final path = _fileInfo()?.filePath;
    if (path == null || !File(path).existsSync()) {
      if (!context.mounted) return;
      // Android 上 MediaStore 展示路径不是真实路径,文件实际在系统"下载"目录
      if (Platform.isAndroid) {
        ReceiveDirectory.openDownloadsFolder();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件不在本机可分享的位置,请打开所在文件夹查看')),
      );
      return;
    }
    await Share.shareXFiles([XFile(path)]);
  }

  /// 打开文件所在文件夹(复用点击文件的逻辑)
  void _openFileFolder(BuildContext context) {
    final path = _fileInfo()?.filePath;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件信息缺失')),
      );
      return;
    }
    _onFileTap(context, path);
  }

  /// 从文件消息的 JSON 内容中解析文件信息
  FileTransferInfo? _fileInfo() {
    try {
      final map = jsonDecode(message.content) as Map<String, dynamic>;
      return FileTransferInfo(
        fileName: map['fileName'] as String? ?? '文件',
        fileSize: map['fileSize'] as int? ?? 0,
        filePath: map['path'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 打开文件所在目录
  Future<void> _openContainingDirectory(BuildContext context, String path) async {
    final dir = p.dirname(path);
    try {
      final ok = await launchUrl(Uri.directory(dir));
      if (!ok && context.mounted) {
        _showErrorDialog(context, '无法打开目录', '没有可用的应用能打开该目录:\n$dir');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, '打开目录失败', '$e');
      }
    }
  }

  /// 显示居中的错误信息弹框:不占满屏幕,内容可滚动查看,带关闭按钮
  void _showErrorDialog(BuildContext context, String title, String message) {
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
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}