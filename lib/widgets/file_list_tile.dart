import 'package:flutter/material.dart';
import '../models/sftp_file_item.dart';

class FileListTile extends StatelessWidget {
  final SftpFileItem file;
  final bool isSelected;
  final bool showRawValues;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const FileListTile({
    super.key,
    required this.file,
    this.isSelected = false,
    this.showRawValues = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withAlpha(80)
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _buildIcon(theme),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: file.isDirectory ? FontWeight.w600 : FontWeight.normal,
                    color: file.isDirectory
                        ? theme.colorScheme.primary
                        : file.isSymbolicLink
                            ? theme.colorScheme.tertiary
                            : textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildMetaInfo(theme, textColor, isMobile),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme) {
    if (file.isSymbolicLink) {
      return Icon(Icons.link, color: theme.colorScheme.tertiary, size: 20);
    }
    if (file.isDirectory) {
      return Icon(Icons.folder, color: theme.colorScheme.primary, size: 20);
    }

    IconData iconData;
    Color color;

    switch (file.extension) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'svg':
        iconData = Icons.image;
        color = Colors.blue;
        break;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        iconData = Icons.video_file;
        color = Colors.purple;
        break;
      case 'mp3':
      case 'wav':
      case 'flac':
        iconData = Icons.audio_file;
        color = Colors.orange;
        break;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'bz2':
      case 'xz':
      case '7z':
        iconData = Icons.archive;
        color = Colors.brown;
        break;
      case 'sh':
      case 'bash':
      case 'zsh':
        iconData = Icons.terminal;
        color = Colors.green;
        break;
      case 'py':
      case 'js':
      case 'ts':
      case 'dart':
      case 'java':
      case 'cpp':
      case 'c':
      case 'rs':
        iconData = Icons.code;
        color = Colors.teal;
        break;
      case 'txt':
      case 'md':
      case 'log':
        iconData = Icons.description;
        color = Colors.grey;
        break;
      case 'conf':
      case 'cfg':
      case 'ini':
      case 'yaml':
      case 'yml':
      case 'json':
      case 'xml':
        iconData = Icons.settings;
        color = Colors.amber;
        break;
      default:
        iconData = Icons.insert_drive_file;
        color = theme.colorScheme.outline;
    }

    return Icon(iconData, color: color, size: 20);
  }

  Widget _buildMetaInfo(ThemeData theme, Color textColor, bool isMobile) {
    final dimColor = textColor.withAlpha(153);
    final sizeText = showRawValues ? '${file.size}' : file.sizeAligned;

    if (isMobile) {
      // Mobile: compact layout with size and date only
      final dateText = _formatDateCompact(file.modifiedAt);
      return DefaultTextStyle(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: dimColor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(sizeText, textAlign: TextAlign.right),
            Text(dateText, style: TextStyle(fontSize: 10, color: dimColor.withAlpha(180))),
          ],
        ),
      );
    }

    // Desktop: full layout with all columns
    final dateText = showRawValues
        ? '${file.modifiedAt.year}-${file.modifiedAt.month.toString().padLeft(2, '0')}-${file.modifiedAt.day.toString().padLeft(2, '0')} ${file.modifiedAt.hour.toString().padLeft(2, '0')}:${file.modifiedAt.minute.toString().padLeft(2, '0')}'
        : file.dateText;

    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: dimColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              file.permissionsText,
              style: TextStyle(color: dimColor),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${file.uid ?? '-'}',
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            child: Text(
              '${file.gid ?? '-'}',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: showRawValues ? 80 : 56,
            child: Text(
              sizeText,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: showRawValues ? 130 : 80,
            child: Text(dateText),
          ),
        ],
      ),
    );
  }

  String _formatDateCompact(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else if (date.year == now.year) {
      return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
  }
}
