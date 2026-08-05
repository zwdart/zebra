import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端无边框窗口的可拖动区域。
///
/// 应用使用无边框窗口(titleBarStyle: hidden),必须由应用提供可拖动区域
/// 才能移动窗口。将该组件包在 AppBar 外,即可在标题栏区域按住拖动窗口;
/// 移动端/Web 端直接透传 child,不产生任何效果。
///
/// 实现 [PreferredSizeWidget]:作为 Scaffold.appBar 使用时,尺寸自动委托给
/// 子组件(子组件为 AppBar 时,高度跟随其工具栏 + 底部 TabBar 的高度),
/// 保证 Scaffold 按正确高度布局 appBar 槽位。
class WindowDragRegion extends StatelessWidget implements PreferredSizeWidget {
  final Widget child;

  const WindowDragRegion({super.key, required this.child});

  @override
  Size get preferredSize {
    if (child is PreferredSizeWidget) {
      return (child as PreferredSizeWidget).preferredSize;
    }
    return const Size.fromHeight(kToolbarHeight);
  }

  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: child,
    );
  }
}
