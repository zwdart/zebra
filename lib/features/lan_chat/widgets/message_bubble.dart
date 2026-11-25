import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/relative_time.dart';
import '../models/lan_models.dart';
import '../protocol/protocol_helpers.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final Conversation conversation;
  final bool showSender;
  final String senderName;
  final bool selectionMode;
  final bool selected;
  final DownloadState? download;
  final SendProgress? sendProgress;
  final VoidCallback? onTap;
  final void Function(Offset position) onMenu;
  final Future<void> Function() onDownload;
  final Future<void> Function() onOpen;
  final Future<void> Function() onShare;
  final VoidCallback onToggleSelect;

  const MessageBubble({
    super.key,
    required this.message,
    required this.conversation,
    this.showSender = false,
    this.senderName = '',
    this.selectionMode = false,
    this.selected = false,
    this.download,
    this.sendProgress,
    this.onTap,
    required this.onMenu,
    required this.onDownload,
    required this.onOpen,
    required this.onShare,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (message.kind == MessageKind.system) {
      return _system(context, loc);
    }
    if (message.recalled) {
      return _recalled(context, loc);
    }
    final isMe = message.mine;
    final scheme = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.of(context).size.width * 0.72;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (selectionMode)
            Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelect(),
              visualDensity: VisualDensity.compact,
            ),
          if (!isMe) _avatar(context),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showSender)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 2),
                    child: Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: selectionMode ? onToggleSelect : onTap,
                  onLongPressStart: (_) => onMenu(_center(context)),
                  onSecondaryTapDown: (d) => onMenu(d.globalPosition),
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    decoration: BoxDecoration(
                      color: isMe
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      border: selected
                          ? Border.all(color: scheme.primary, width: 2)
                          : null,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                    ),
                    padding: message.kind == MessageKind.image
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                    child: _content(context, loc, isMe),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 6, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMe) _sendState(context, loc),
                      if (isMe) const SizedBox(width: 4),
                      Text(
                        RelativeTime.messageTime(loc, message.sentAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Offset _center(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Widget _avatar(BuildContext context) {
    final name = senderName.trim();
    return CircleAvatar(
      radius: 15,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _system(BuildContext context, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _recalled(BuildContext context, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 3),
      child: Center(
        child: Text(
          '${message.mine ? loc.translate('you') : senderName} ${loc.translate('messageRecalled')}',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppLocalizations loc, bool isMe) {
    switch (message.kind) {
      case MessageKind.text:
        return SelectableText(
          message.text,
          style: const TextStyle(fontSize: 15, height: 1.35),
        );
      case MessageKind.image:
        return _image(context, loc);
      case MessageKind.file:
        return _file(context, loc, isMe);
      case MessageKind.system:
        return Text(message.text);
    }
  }

  Widget _image(BuildContext context, AppLocalizations loc) {
    final file = message.file;
    final path = file?.path ?? '';
    final hasFile = path.isNotEmpty && File(path).existsSync();
    final dl = download;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: hasFile
            ? GestureDetector(
                onTap: () => onOpen(),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _imagePlaceholder(context, loc, file, dl),
                ),
              )
            : _imagePlaceholder(context, loc, file, dl),
      ),
    );
  }

  Widget _imagePlaceholder(
    BuildContext context,
    AppLocalizations loc,
    FileMeta? file,
    DownloadState? dl,
  ) {
    final working = dl?.working ?? false;
    final value = dl?.value ?? 0;
    return Container(
      width: 220,
      height: 160,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (working) ...[
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(value: value),
            ),
            const SizedBox(height: 8),
            Text('${(value * 100).round()}%'),
          ] else ...[
            const Icon(Icons.image_outlined, size: 42),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                file?.name ?? loc.translate('imageLabel'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (dl?.error.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  dl!.error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download, size: 18),
              label: Text(loc.translate('download')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _file(BuildContext context, AppLocalizations loc, bool isMe) {
    final file = message.file;
    final dl = download;
    final sp = sendProgress;
    final working = (dl != null && dl.working) || (sp != null && sp.working);
    final value = isMe ? (sp?.value ?? 0) : (dl?.value ?? 0);
    final error = isMe ? (sp?.error ?? '') : (dl?.error ?? '');
    final exists =
        file != null && file.path.isNotEmpty && File(file.path).existsSync();
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                exists ? Icons.insert_drive_file : Icons.description_outlined,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file?.name ?? loc.translate('fileDefaultName'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      humanSize(file?.size ?? 0),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (working) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: value > 0 ? value : null),
            const SizedBox(height: 4),
            Text(
              isMe && sp != null
                  ? '${humanSize(sp.sent)} / ${humanSize(sp.total)}'
                  : '${(value * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              if (!isMe && !exists)
                TextButton.icon(
                  onPressed: working ? null : onDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(loc.translate('download')),
                ),
              if (exists)
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(loc.translate('open')),
                ),
              if (exists)
                IconButton(
                  tooltip: loc.translate('share'),
                  icon: const Icon(Icons.ios_share, size: 18),
                  onPressed: onShare,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sendState(BuildContext context, AppLocalizations loc) {
    final sp = sendProgress;
    if (sp != null && sp.working) {
      return SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          value: sp.value > 0 ? sp.value : null,
        ),
      );
    }
    if (sp != null && sp.error.isNotEmpty) {
      return Icon(
        Icons.error_outline,
        size: 13,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (message.read) {
      return Icon(
        Icons.done_all,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    if (message.delivered) {
      return Icon(
        Icons.done_all,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return Icon(
      Icons.done,
      size: 14,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
