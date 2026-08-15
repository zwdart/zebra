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

/// 边缘热区：按下并拖动时，用 [WindowManager.setBounds] 手动计算窗口
/// 新矩形，实现宽高/位置调整。
///
/// 不调用 [WindowManager.startResizing]：该 API 在 Windows 上通过异步
/// PostMessage(WM_NCLBUTTONDOWN) 请求系统进入缩放模态循环，在 Flutter
/// 引擎窗口下常因时序/捕获问题不生效（表现为光标出现但拖不动）。
/// 手动 setBounds 不依赖系统模态循环，各平台行为一致可靠。
class _EdgeRegion extends StatefulWidget {
  final ResizeEdge edge;
  final MouseCursor cursor;

  const _EdgeRegion({required this.edge, required this.cursor});

  @override
  State<_EdgeRegion> createState() => _EdgeRegionState();
}

class _EdgeRegionState extends State<_EdgeRegion> {
  /// 缩放最小尺寸（逻辑像素），避免拖到负值/窗口塌陷
  static const double _minWidth = 400;
  static const double _minHeight = 300;

  /// 按下时的窗口矩形（拖拽基准，避免增量误差累积）
  Rect? _startBounds;

  /// 按下时的指针全局坐标（逻辑像素）
  Offset? _startPos;

  Future<void> _onPointerDown(PointerDownEvent event) async {
    // 最大化时不允许拖动缩放
    if (await windowManager.isMaximized()) return;
    _startBounds = await windowManager.getBounds();
    _startPos = event.position;
  }

  Future<void> _onPointerMove(PointerMoveEvent event) async {
    final start = _startBounds;
    final origin = _startPos;
    if (start == null || origin == null) return;
    final delta = event.position - origin;
    await windowManager.setBounds(_resizeRect(start, delta));
  }

  void _onPointerUp(PointerUpEvent event) {
    _startBounds = null;
    _startPos = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _startBounds = null;
    _startPos = null;
  }

  /// 根据拖拽增量计算新的窗口矩形（逻辑像素）。
  Rect _resizeRect(Rect start, Offset delta) {
    double left = start.left;
    double top = start.top;
    double right = start.right;
    double bottom = start.bottom;

    switch (widget.edge) {
      case ResizeEdge.top:
        top += delta.dy;
        break;
      case ResizeEdge.bottom:
        bottom += delta.dy;
        break;
      case ResizeEdge.left:
        left += delta.dx;
        break;
      case ResizeEdge.right:
        right += delta.dx;
        break;
      case ResizeEdge.topLeft:
        top += delta.dy;
        left += delta.dx;
        break;
      case ResizeEdge.topRight:
        top += delta.dy;
        right += delta.dx;
        break;
      case ResizeEdge.bottomLeft:
        bottom += delta.dy;
        left += delta.dx;
        break;
      case ResizeEdge.bottomRight:
        bottom += delta.dy;
        right += delta.dx;
        break;
    }

    // 钳制最小宽高：缩小时优先保持固定边不动，移动对侧边
    if (right - left < _minWidth) {
      if (widget.edge == ResizeEdge.left ||
          widget.edge == ResizeEdge.topLeft ||
          widget.edge == ResizeEdge.bottomLeft) {
        left = right - _minWidth;
      } else {
        right = left + _minWidth;
      }
    }
    if (bottom - top < _minHeight) {
      if (widget.edge == ResizeEdge.top ||
          widget.edge == ResizeEdge.topLeft ||
          widget.edge == ResizeEdge.topRight) {
        top = bottom - _minHeight;
      } else {
        bottom = top + _minHeight;
      }
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _onPointerDown(e),
        onPointerMove: (e) => _onPointerMove(e),
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
      ),
    );
  }
}
