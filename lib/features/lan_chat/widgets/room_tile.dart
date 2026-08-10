import 'package:flutter/material.dart';
import '../models/lan_device.dart';
import '../../../l10n/app_localizations.dart';

/// 附近房间列表项(来自心跳 room 摘要的设备)
class RoomTile extends StatelessWidget {
  final LanDevice device; // device.roomInfo 为房间摘要
  final VoidCallback? onJoin;

  const RoomTile({super.key, required this.device, this.onJoin});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final info = device.roomInfo;
    if (info == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(Icons.groups, color: colorScheme.onPrimaryContainer),
        ),
        title: Text(
          info.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            Icon(Icons.lan, size: 12, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              '${device.name} · ${device.ip}:${info.port}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).roomMemberCountValue(info.memberCount),
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            if (device.isOnline && onJoin != null)
              FilledButton.tonal(
                onPressed: onJoin,
                child: Text(AppLocalizations.of(context).joinRoom),
              ),
          ],
        ),
      ),
    );
  }
}
