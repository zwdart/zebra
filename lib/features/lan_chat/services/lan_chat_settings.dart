import 'package:shared_preferences/shared_preferences.dart';

/// 本地聊天的端口与提醒设置
///
/// 说明:
/// - 发现端口(UDP 广播)是"双方约定一致"的端口,默认 19422;
///   允许手动配置用于绕开端口占用,但非默认值会提示用户可能搜不到其他客户端。
/// - 聊天端口(TCP)真实端口会随心跳广播给对方,默认 22066,无需两端一致。
class LanChatSettings {
  LanChatSettings._();

  /// 默认发现端口(UDP 广播)
  static const int defaultDiscoveryPort = 19422;

  /// 默认聊天端口(TCP,真实端口随心跳广播给对方)
  static const int defaultChatPort = 22066;

  static const _discoveryPortKey = 'lan_chat_discovery_port';
  static const _warningDateKey = 'lan_chat_discovery_warning_date';

  /// 读取手动配置的发现端口,null 表示使用默认端口
  static Future<int?> getDiscoveryPort() async {
    final prefs = await SharedPreferences.getInstance();
    final port = prefs.getInt(_discoveryPortKey);
    if (port == null || port <= 0 || port > 65535) return null;
    return port;
  }

  /// 保存手动配置的发现端口;传 null(或非法值)恢复默认
  static Future<void> setDiscoveryPort(int? port) async {
    final prefs = await SharedPreferences.getInstance();
    if (port == null || port <= 0 || port > 65535) {
      await prefs.remove(_discoveryPortKey);
    } else {
      await prefs.setInt(_discoveryPortKey, port);
    }
  }

  /// 今天是否已提醒过"发现端口非默认"(每天最多提醒一次)
  static Future<bool> isWarningShownToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_warningDateKey) == _today();
  }

  /// 记录今天已提醒
  static Future<void> markWarningShownToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_warningDateKey, _today());
  }

  static String _today() =>
      DateTime.now().toIso8601String().substring(0, 10);
}
