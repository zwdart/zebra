import 'package:flutter/material.dart';
import '../models/chat_message.dart';

/// 文件传输进度条组件
class FileTransferTile extends StatelessWidget {
  final FileTransferInfo transfer;

  const FileTransferTile({super.key, required this.transfer});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isSend = transfer.direction == TransferDirection.send;
    final icon = isSend ? Icons.upload_file : Icons.download;
    final statusText = _statusText();
    final statusColor = _statusColor(colorScheme);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 28, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transfer.fileName,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (transfer.status == TransferStatus.transferring) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: transfer.progress,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(transfer.progress * 100).toStringAsFixed(0)}% / ${transfer.sizeFormatted}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    switch (transfer.status) {
      case TransferStatus.pending:
        return '等待中...';
      case TransferStatus.transferring:
        return '传输中...';
      case TransferStatus.done:
        return '传输完成';
      case TransferStatus.failed:
        return transfer.errorMessage ?? '传输失败';
      case TransferStatus.cancelled:
        return '已取消';
    }
  }

  Color _statusColor(ColorScheme colorScheme) {
    switch (transfer.status) {
      case TransferStatus.done:
        return Colors.green;
      case TransferStatus.failed:
        return colorScheme.error;
      case TransferStatus.cancelled:
        return colorScheme.onSurfaceVariant;
      default:
        return colorScheme.primary;
    }
  }
}