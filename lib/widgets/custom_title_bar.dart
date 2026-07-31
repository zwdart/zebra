import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../l10n/app_localizations.dart';

class CustomTitleBar extends StatelessWidget {
  final String? title;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBack;
  final bool showCloseButton;
  final VoidCallback? onClose;

  const CustomTitleBar({
    super.key,
    this.title,
    this.actions,
    this.showBackButton = false,
    this.onBack,
    this.showCloseButton = false,
    this.onClose,
  });

  static bool get isDesktop => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        windowManager.startDragging();
      },
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            if (showBackButton)
              _WindowButton(
                icon: Icons.arrow_back,
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
                tooltip: loc.back,
              )
            else ...[
              const SizedBox(width: 12),
              Image.asset(
                'assets/icons/icon.png',
                width: 20,
                height: 20,
              ),
            ],
            if (showCloseButton)
              _WindowButton(
                icon: Icons.close,
                onTap: onClose ?? () => Navigator.of(context).maybePop(),
                tooltip: loc.exitSftp,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title ?? 'Zebra SSH',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (actions != null) ...actions!,
            const SizedBox(width: 8),
            _WindowButton(
              icon: Icons.remove,  // 横线 - 最小化
              onTap: () => windowManager.minimize(),
              tooltip: loc.minimize,
            ),
            _MaximizeButton(),
            _WindowButton(
              icon: Icons.close,  // X - 关闭
              onTap: () async {
                await windowManager.close();
              },
              tooltip: loc.close,
              isClose: true,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> {
  bool _isMaximized = false;
  final _listener = _WindowEventListener();

  @override
  void initState() {
    super.initState();
    _checkMaximized();
    _listener.onChanged = _checkMaximized;
    windowManager.addListener(_listener);
  }

  @override
  void dispose() {
    windowManager.removeListener(_listener);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted && _isMaximized != isMaximized) {
      setState(() => _isMaximized = isMaximized);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WindowButton(
      icon: _isMaximized
          ? Icons.fullscreen_exit  // 还原 (两个重叠方块)
          : Icons.fullscreen,      // 最大化 (方块)
      onTap: () async {
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      tooltip: _isMaximized ? 'Restore' : 'Maximize',
    );
  }
}

class _WindowEventListener extends WindowListener {
  VoidCallback? onChanged;

  @override
  void onWindowMaximize() => onChanged?.call();

  @override
  void onWindowUnmaximize() => onChanged?.call();

  @override
  void onWindowRestore() => onChanged?.call();
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: isClose
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
