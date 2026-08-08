import 'dart:io';
import 'package:flutter/services.dart';

/// 传输期间保持设备"清醒",防止熄屏/自动锁屏后进程挂起导致传输停滞。
///
/// 不依赖第三方库,双平台走原生实现:
/// - Android: WindowManager.FLAG_KEEP_SCREEN_ON(屏幕常亮,无权限要求);
/// - iOS: UIApplication.isIdleTimerEnabled = false(禁止自动锁屏)。
/// 引用计数:多个传输同时进行时只点亮一次,全部结束后才恢复系统熄屏策略。
class ScreenKeepOn {
  static const MethodChannel _channel = MethodChannel('xin.dart.zebra/screen');
  static int _holders = 0;

  /// 增加一个持有者;首个持有者才真正点亮/阻止锁屏。
  static Future<void> acquire() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _holders++;
    if (_holders == 1) {
      try {
        await _channel.invokeMethod<void>('setKeepScreenOn', {'on': true});
      } catch (_) {
        // 原生侧不可用时忽略(理论上只会在 Android/iOS 走到这里)
      }
    }
  }

  /// 减少一个持有者;全部释放后恢复系统熄屏策略。
  static Future<void> release() async {
    if ((!Platform.isAndroid && !Platform.isIOS) || _holders <= 0) return;
    _holders--;
    if (_holders == 0) {
      try {
        await _channel.invokeMethod<void>('setKeepScreenOn', {'on': false});
      } catch (_) {}
    }
  }
}
