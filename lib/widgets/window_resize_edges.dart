import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../services/native_window_resize.dart';

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

/// 边缘热区：按下时通过 [NativeWindowResize] 进入系统原生缩放模态循环。
///
/// 不调用 [WindowManager.startResizing]：该 API 在 Windows 上通过异步
/// PostMessage(WM_NCLBUTTONDOWN) 请求系统进入缩放模态循环，在 Flutter
/// 引擎窗口下常因时序/捕获问题不生效（表现为光标出现但拖不动）。
/// 改为 Dart FFI 直调 user32 SendMessage(WM_SYSCOMMAND, SC_SIZE) 同步
/// 触发系统模态循环，由系统接管窗口绘制，无残影闪烁（与 RustDesk 一致）。
class _EdgeRegion extends StatefulWidget {
  final ResizeEdge edge;
  final MouseCursor cursor;

  const _EdgeRegion({required this.edge, required this.cursor});

  @override
  State<_EdgeRegion> createState() => _EdgeRegionState();
}

class _EdgeRegionState extends State<_EdgeRegion> {
  Future<void> _onPointerDown(PointerDownEvent event) async {
    // 最大化时不允许拖动缩放
    if (await windowManager.isMaximized()) return;
    // 进入系统原生缩放模态循环：SendMessage 同步阻塞直到用户松开鼠标，
    // 缩放由系统接管绘制，无残影闪烁。返回后缩放已完成。
    await NativeWindowResize.startResizing(widget.edge);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _onPointerDown(e),
      ),
    );
  }
}
