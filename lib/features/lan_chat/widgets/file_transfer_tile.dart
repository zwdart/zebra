import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/file_transfer_session.dart';
import '../../../l10n/app_localizations.dart';

/// 文件传输进度条组件:展示文件名、进度、速度、剩余时间与已用时间,
/// 传输中提供取消控制。
class FileTransferTile extends StatelessWidget {
  final FileTransferSession session;
  final VoidCallback? onCancel;

  const FileTransferTile({
    super.key,
    required this.session,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isSend = session.direction == TransferDirection.send;
    final icon = isSend ? Icons.upload_file : Icons.download;
    final statusText = _statusText(context);
    final statusColor = _statusColor(colorScheme);
    final transfer = session.info;

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
                  if (transfer.status == TransferStatus.transferring ||
                      transfer.status == TransferStatus.pending) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: transfer.status == TransferStatus.pending
                            ? 0.0
                            : transfer.progress,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(transfer.progress * 100).toStringAsFixed(0)}% '
                      '${FileTransferInfo.formatSize(session.transferredBytes)} / ${transfer.sizeFormatted}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // pending 显示排队中文案;传输中显示速度/剩余时间
                    // (小文件传输太快,速度/剩余无意义,不再显示第二行)
                    if (transfer.status == TransferStatus.pending)
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else if (session.fileSize > kSmallFileThresholdBytes)
                      Text(
                        session.progressLine(
                          remainingLabel: AppLocalizations.of(context).remainingTimeLabel,
                        ),
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
            // 控制按钮:取消(pending 排队/卡住时也提供取消,防止无法中止)
            if (transfer.status == TransferStatus.transferring ||
                transfer.status == TransferStatus.pending)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: AppLocalizations.of(context).cancel,
                onPressed: onCancel,
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(BuildContext context) {
    final loc = AppLocalizations.of(context);
    switch (session.status) {
      case TransferStatus.pending:
        return loc.transferPending;
      case TransferStatus.transferring:
        return loc.transferTransferring;
      case TransferStatus.done:
        return loc.transferDone;
      case TransferStatus.failed:
        return session.errorMessage ?? loc.transferFailed;
      case TransferStatus.cancelled:
        return loc.transferCancelled;
    }
  }

  Color _statusColor(ColorScheme colorScheme) {
    switch (session.status) {
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
