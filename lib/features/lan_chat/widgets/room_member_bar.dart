import 'package:flutter/material.dart';
import '../models/room.dart';

/// 聊天室成员横条:横向滚动展示成员头像与名字
class RoomMemberBar extends StatelessWidget {
  final List<RoomMember> members;
  final ValueChanged<RoomMember>? onMemberTap; // 点击成员(可查看详情/发起私聊)

  const RoomMemberBar({super.key, required this.members, this.onMemberTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (members.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: members.length,
        itemBuilder: (ctx, i) {
          final m = members[i];
          final firstChar = m.deviceName.isNotEmpty ? m.deviceName[0].toUpperCase() : '?';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onMemberTap == null ? null : () => onMemberTap!(m),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      firstChar,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 64),
                    child: Text(
                      m.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
