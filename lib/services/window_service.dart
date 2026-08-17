import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';

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

    // 窗口背景色与应用主题背景保持一致，避免无边框窗口四周露出的
    // 8px 系统边框(见 window_resize_edges.dart 说明)与应用内容颜色不一致。
    final backgroundColor = _themeBackgroundColor(prefs);

    final windowOptions = WindowOptions(
      size: Size(width, height),
      center: x == null && y == null,
      backgroundColor: backgroundColor,
      titleBarStyle: TitleBarStyle.hidden,
      // macOS 上隐藏原生红绿灯按钮(关闭/最小化/全屏),与 Windows/Linux
      // 自绘标题栏保持一致;关闭/最小化由 CustomTitleBar 自绘按钮提供
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      // Windows: 隐藏标题栏后 window_manager 的 NCCALCSIZE 会把客户区
      // 四周缩 8px 留给系统 resize 边框(issue #483 的 hack),导致窗口
      // 边缘露出与应用内容颜色不一致的 8px 边框(白/深蓝)。改用手动
      // setBounds 缩放后不再需要系统边框,调用 setAsFrameless() 让客户区
      // 铺满整个窗口,彻底消除该边框。必须在 waitUntilReadyToShow(内部
      // 执行 SetTitleBarStyle 会重置 frameless 标记)之后调用。
      if (!kIsWeb && Platform.isWindows) {
        await windowManager.setAsFrameless();
      }
      await windowManager.show();
      await windowManager.focus();
      if (isMaximized) {
        await windowManager.maximize();
      }
    });

    windowManager.addListener(_WindowListener());
  }

  /// 窗口状态保存防抖计时器：拖拽调整窗口时 move/resize 事件高频触发，
  /// 若每次都立即写 SharedPreferences 会卡顿闪烁，改为停止变化后再保存。
  static Timer? _saveDebounce;

  /// 延迟保存窗口状态（防抖），供 move/resize/maximize 等高频事件调用。
  static void scheduleSave() {
    if (!isDesktop) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      saveState();
    });
  }

  static Future<void> saveState() async {
    if (!isDesktop) return;
    _saveDebounce?.cancel();
    _saveDebounce = null;

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

  /// 根据持久化的主题设置计算窗口背景色（与应用主题背景一致）。
  ///
  /// window_manager 在 Windows 上会把该颜色作为窗口四周 8px 系统边框
  /// 区域的填充色，因此必须与 Flutter 内容的背景色相同，否则边框区域
  /// 会与应用内容颜色不一致（或透明背景时露出 DWM 的浅蓝渐变边框）。
  static Color _themeBackgroundColor(SharedPreferences prefs) {
    final modeIndex = prefs.getInt('themeMode') ?? 0;
    final mode = ThemeMode.values[modeIndex];
    final seedValue = prefs.getInt('seedColor');
    final seed = seedValue != null ? Color(seedValue) : Colors.blue;
    final isDark = switch (mode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    final theme = isDark ? AppTheme.dark(seed) : AppTheme.light(seed);
    return theme.scaffoldBackgroundColor;
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
    WindowService.scheduleSave();
  }

  @override
  void onWindowMove() {
    WindowService.scheduleSave();
  }

  @override
  void onWindowMaximize() {
    WindowService.scheduleSave();
  }

  @override
  void onWindowUnmaximize() {
    WindowService.scheduleSave();
  }
}
