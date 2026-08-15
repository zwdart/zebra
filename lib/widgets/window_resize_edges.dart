import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端无边框窗口的边缘缩放热区。
///
/// 应用使用无边框窗口(titleBarStyle: hidden)。Windows 上隐藏标题栏后系统
/// resize 边框会失效(参见 window_manager issue #483/#443),导致无法拖动
/// 窗口边缘调整大小。此组件在窗口四边/四角覆盖一层透明热区,按下时调用
/// [WindowManager.startResizing] 进入系统缩放流程,恢复边缘拖拽调整大小。
/// 仅 Windows 启用：Linux/macOS 系统边框缩放可用，且 macOS 原生没有
/// startResizing 实现，无需热区。移动端/Web 端直接透传 child，不产生任何效果。
class WindowResizeEdges extends StatelessWidget {
  final Widget child;

  const WindowResizeEdges({super.key, required this.child});

  /// 热区厚度：四边宽度
  static const double _thickness = 6;

  /// 四角热区边长（大于厚度，便于命中斜角）
  static const double _corner = 12;

  /// 仅 Windows 需要热区（无边框窗口系统 resize 边框在该平台失效）
  static bool get _enabled => !kIsWeb && Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return child;

    return Stack(
      children: [
        child,
        // 四条边
        Positioned(
          left: _corner,
          top: 0,
          right: _corner,
          height: _thickness,
          child: _EdgeRegion(
            edge: ResizeEdge.top,
            cursor: SystemMouseCursors.resizeUpDown,
          ),
        ),
        Positioned(
          left: _corner,
          bottom: 0,
          right: _corner,
          height: _thickness,
          child: _EdgeRegion(
            edge: ResizeEdge.bottom,
            cursor: SystemMouseCursors.resizeUpDown,
          ),
        ),
        Positioned(
          left: 0,
          top: _corner,
          bottom: _corner,
          width: _thickness,
          child: _EdgeRegion(
            edge: ResizeEdge.left,
            cursor: SystemMouseCursors.resizeLeftRight,
          ),
        ),
        Positioned(
          right: 0,
          top: _corner,
          bottom: _corner,
          width: _thickness,
          child: _EdgeRegion(
            edge: ResizeEdge.right,
            cursor: SystemMouseCursors.resizeLeftRight,
          ),
        ),
        // 四个角
        Positioned(
          left: 0,
          top: 0,
          width: _corner,
          height: _corner,
          child: _EdgeRegion(
            edge: ResizeEdge.topLeft,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          width: _corner,
          height: _corner,
          child: _EdgeRegion(
            edge: ResizeEdge.topRight,
            cursor: SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
          child: _EdgeRegion(
            edge: ResizeEdge.bottomLeft,
            cursor: SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
          child: _EdgeRegion(
            edge: ResizeEdge.bottomRight,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
      ],
    );
  }
}

class _EdgeRegion extends StatelessWidget {
  final ResizeEdge edge;
  final MouseCursor cursor;

  const _EdgeRegion({required this.edge, required this.cursor});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 必须用 onPanStart(手势识别完成)而非 onPointerDown 触发：
        // Windows 上按下瞬间 Flutter 引擎仍持有鼠标捕获/尚未释放指针，
        // 此时调用 startResizing 发送的 WM_NCLBUTTONDOWN 无法进入系统
        // 缩放模态循环，表现为光标出现但拖不动（与官方 DragToResizeArea、
        // WindowDragRegion 的 startDragging 一致，参见 window_manager #399）。
        // 手势识别（越过 slop）后引擎已释放指针，系统才接管缩放。
        onPanStart: (_) => windowManager.startResizing(edge).ignore(),
      ),
    );
  }
}
