import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 系统原生缩放桥接（Dart FFI 直调 user32.dll）。
///
/// window_manager 官方 [WindowManager.startResizing] 在 Windows 上通过异步
/// PostMessage(WM_NCLBUTTONDOWN) 请求系统进入缩放模态循环，在 Flutter
/// 引擎窗口下常因时序/鼠标捕获问题不生效（表现为光标出现但拖不动）。
///
/// 本桥接改用**同步** [SendMessageW] 发送 WM_SYSCOMMAND SC_SIZE：
/// 消息直达窗口过程时鼠标按钮必然仍处于按下状态，DefWindowProc 随即进入
/// 系统模态缩放循环，由系统接管窗口绘制——与 RustDesk 的原生体验一致，
/// 无残影、无闪烁。调用会阻塞直到用户松开鼠标，模态循环结束后返回。
///
/// 仅 Windows 生效；其他平台调用为空操作。
class NativeWindowResize {
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  /// BOOL ReleaseCapture(void);
  static final int Function() _releaseCapture = _user32
      .lookupFunction<Int32 Function(), int Function()>('ReleaseCapture');

  /// LRESULT SendMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
  static final int Function(int, int, int, int) _sendMessage = _user32
      .lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)>('SendMessageW');

  static const int _wmSyscommand = 0x0112;
  static const int _scSize = 0xF000;

  /// WMSZ_* 边缘码（WM_SYSCOMMAND SC_SIZE 的 wParam 低位）。
  static const Map<ResizeEdge, int> _wmsz = {
    ResizeEdge.left: 1,
    ResizeEdge.right: 2,
    ResizeEdge.top: 3,
    ResizeEdge.topLeft: 4,
    ResizeEdge.topRight: 5,
    ResizeEdge.bottom: 6,
    ResizeEdge.bottomLeft: 7,
    ResizeEdge.bottomRight: 8,
  };

  /// 进入系统原生缩放模态循环（阻塞直到用户松开鼠标）。
  static Future<void> startResizing(ResizeEdge edge) async {
    if (!isSupported) return;
    final hwnd = await windowManager.getId();
    if (hwnd == 0) return;
    final code = _wmsz[edge];
    if (code == null) return;
    // 解除 Flutter 引擎可能持有的鼠标捕获，模态循环才能收到鼠标消息
    _releaseCapture();
    // 同步发送，系统接管缩放；返回即缩放结束
    _sendMessage(hwnd, _wmSyscommand, _scSize | code, 0);
  }
}
