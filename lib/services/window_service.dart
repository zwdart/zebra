import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  static const _keyWidth = 'window_width';
  static const _keyHeight = 'window_height';
  static const _keyX = 'window_x';
  static const _keyY = 'window_y';
  static const _keyMaximized = 'window_maximized';

  static bool get isDesktop => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  static Future<void> init() async {
    if (!isDesktop) return;

    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble(_keyWidth) ?? 1200.0;
    final height = prefs.getDouble(_keyHeight) ?? 800.0;
    final x = prefs.getDouble(_keyX);
    final y = prefs.getDouble(_keyY);
    final isMaximized = prefs.getBool(_keyMaximized) ?? false;

    final windowOptions = WindowOptions(
      size: Size(width, height),
      center: x == null && y == null,
      backgroundColor: const Color(0xFF1E1E2E),
      titleBarStyle: TitleBarStyle.hidden,
      // macOS 上隐藏原生红绿灯按钮(关闭/最小化/全屏),与 Windows/Linux
      // 自绘标题栏保持一致;关闭/最小化由 CustomTitleBar 自绘按钮提供
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      await windowManager.show();
      await windowManager.focus();
      if (isMaximized) {
        await windowManager.maximize();
      }
    });

    windowManager.addListener(_WindowListener());
  }

  static Future<void> saveState() async {
    if (!isDesktop) return;

    final prefs = await SharedPreferences.getInstance();
    final isMaximized = await windowManager.isMaximized();

    if (!isMaximized) {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      await prefs.setDouble(_keyWidth, size.width);
      await prefs.setDouble(_keyHeight, size.height);
      await prefs.setDouble(_keyX, position.dx);
      await prefs.setDouble(_keyY, position.dy);
    }
    await prefs.setBool(_keyMaximized, isMaximized);
  }
}

class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await WindowService.saveState();
    await windowManager.destroy();
  }

  @override
  void onWindowResized() {
    WindowService.saveState();
  }

  @override
  void onWindowMove() {
    WindowService.saveState();
  }

  @override
  void onWindowMaximize() {
    WindowService.saveState();
  }

  @override
  void onWindowUnmaximize() {
    WindowService.saveState();
  }
}
