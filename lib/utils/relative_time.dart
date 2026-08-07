import '../l10n/app_localizations.dart';

/// 相对时间格式化工具:统一聊天相关的时间显示规则,
/// 避免消息气泡与会话列表各写一份重复逻辑。
class RelativeTime {
  RelativeTime._();

  /// 消息气泡内的时间:刚刚 / x分钟前 / 当天 HH:mm / 更早 M/d HH:mm
  static String messageTime(AppLocalizations loc, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return loc.timeJustNow;
    if (diff.inHours < 1) return loc.timeMinutesAgoValue(diff.inMinutes);
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 会话列表的最后消息时间:刚刚 / x分钟前 / 当天 HH:mm / 7 天内 M/d / 更早 yyyy/M/d
  static String peerTime(AppLocalizations loc, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return loc.timeJustNow;
    if (diff.inHours < 1) return loc.timeMinutesAgoValue(diff.inMinutes);
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${dt.month}/${dt.day}';
    return '${dt.year}/${dt.month}/${dt.day}';
  }
}
