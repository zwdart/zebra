import 'package:flutter/material.dart';
import '../models/lan_device.dart';
import '../../../l10n/app_localizations.dart';

/// 设备列表项组件
class DeviceTile extends StatelessWidget {
  final LanDevice device;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;
  final VoidCallback? onDelete;

  const DeviceTile({
    super.key,
    required this.device,
    this.onTap,
    this.onConnect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: device.isOnline
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.computer,
            color: device.isOnline
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          device.name,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: device.isOnline
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(Icons.lan, size: 12, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              '${device.ip}:${device.port}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: device.isOnline
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: device.isOnline ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            if (device.isOnline && onConnect != null)
              FilledButton.tonal(
                onPressed: onConnect,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(AppLocalizations.of(context).chat, style: const TextStyle(fontSize: 12)),
              ),
            // 离线设备提供删除入口,用于清理残留条目
            if (!device.isOnline && onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: AppLocalizations.of(context).deleteDevice,
                onPressed: onDelete,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}