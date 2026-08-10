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
        // 标题行:房间名(长名省略号) + 成员数,避免长房名撑高/挤掉按钮
        title: Row(
          children: [
            Expanded(
              child: Text(
                info.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context).roomMemberCountValue(info.memberCount),
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        // 副标题:设备名与地址(长名省略号),整行可压缩
        subtitle: Row(
          children: [
            Icon(Icons.lan, size: 12, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${device.name} · ${device.ip}:${info.port}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        // trailing 只保留加入按钮(紧凑),不再塞成员数,手机上不再挤压标题
        trailing: (device.isOnline && onJoin != null)
            ? FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: onJoin,
                child: Text(AppLocalizations.of(context).joinRoom),
              )
            : null,
      ),
    );
  }
}
