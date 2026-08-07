import 'chat_message.dart';

/// 小文件阈值:小于等于该大小的文件走快速通道
/// (接收侧内存缓冲直接落盘,不建 .part;UI 不显示速度/剩余时间)
const int kSmallFileThresholdBytes = 2 * 1024 * 1024; // 2MB

/// 文件传输采样点(时间, 累计已传字节)
typedef _TransferSample = ({DateTime time, int bytes});

/// 一次文件传输的会话:内聚传输元信息、开始时间、采样点,
/// 并提供速度/剩余时间/已用时间等运行时能力。
///
/// 与 [FileTransferInfo] 的区别:Info 是消息内容(可序列化/入库)的映射,
/// Session 是运行时的传输状态载体,不参与序列化,UI 直接读取其计算属性。
///
/// 方案 A 简化:无暂停/恢复、无断点续传,传输要么进行、要么取消/失败。
class FileTransferSession {
  FileTransferSession({required this.transferId, required FileTransferInfo info})
      : _info = info,
        _startedAt = DateTime.now();

  final String transferId;
  final DateTime _startedAt;
  FileTransferInfo _info;

  /// 当前已传字节数(发送=已发出,接收=已落盘);仅用于进度展示,不参与续传
  int offset = 0;

  /// 采样点队列,用于滑动窗口计算瞬时速度(只保留最近 [sampleWindow] 的点)
  final List<_TransferSample> _samples = [];
  static const Duration _sampleWindow = Duration(seconds: 30);
  /// 采样节流:传输中最多每 [sampleInterval] 记录一次采样,
  /// 避免 64KB chunk 高频触发时队列无限膨胀(大文件传输的关键优化)。
  static const Duration _sampleInterval = Duration(milliseconds: 300);
  DateTime? _lastSampleAt;

  /// 取消传输:标记取消(发送循环据此中止)
  void cancel() {
    _info = _info.copyWith(status: TransferStatus.cancelled);
  }

  // ---- 只读透传 ----
  FileTransferInfo get info => _info;
  TransferStatus get status => _info.status;
  double get progress => _info.progress;
  int get fileSize => _info.fileSize;
  String get fileName => _info.fileName;
  String? get filePath => _info.filePath;
  TransferDirection get direction => _info.direction;
  String? get errorMessage => _info.errorMessage;

  /// 已传输字节数(由进度推算)
  int get transferredBytes => (progress * fileSize).round();

  /// 更新传输状态并记录采样点
  void update({TransferStatus? status, double? progress, String? errorMessage}) {
    _info = _info.copyWith(
      status: status,
      progress: progress,
      errorMessage: errorMessage,
    );
    _maybeRecordSample();
  }

  /// 已用时间
  Duration get elapsed => DateTime.now().difference(_startedAt);

  /// 平均速度(字节/秒)
  double get averageSpeed {
    final secs = elapsed.inMilliseconds / 1000;
    if (secs <= 0) return 0;
    return transferredBytes / secs;
  }

  /// 瞬时速度(字节/秒):最近 [instantWindow] 内的采样滑动窗口,
  /// 采样不足时回退到平均速度,避免刚起步时速度虚高/为 0。
  double get instantaneousSpeed {
    if (_samples.length < 2) return averageSpeed;
    final cutoff = DateTime.now().subtract(_instantWindow);
    final window = _samples.where((s) => !s.time.isBefore(cutoff)).toList();
    if (window.length < 2) return averageSpeed;
    final dtMs = window.last.time.difference(window.first.time).inMilliseconds;
    if (dtMs <= 0) return averageSpeed;
    return (window.last.bytes - window.first.bytes) / (dtMs / 1000);
  }

  static const Duration _instantWindow = Duration(seconds: 2);

  /// 剩余时间估算:基于瞬时速度;速度过小或已结束返回 null
  Duration? get remaining {
    final speed = instantaneousSpeed;
    if (speed <= 0) return null;
    final left = (fileSize - transferredBytes).clamp(0, fileSize);
    if (left <= 0) return Duration.zero;
    return Duration(seconds: (left / speed).round());
  }

  /// 速度文本,如 3.2 MB/s;速度不可用时返回 '--'
  String get speedText {
    final speed = instantaneousSpeed;
    if (speed <= 0) return '--';
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// 传输进度摘要行:速度 · 剩余 xx(label 由调用方传入以支持本地化)
  String progressLine({required String remainingLabel}) {
    return '$speedText · $remainingLabel $remainingText';
  }

  /// 剩余时间文本;无法估算时返回 '--'
  String get remainingText {
    final r = remaining;
    if (r == null) return '--';
    return FileTransferSession.formatDuration(r);
  }

  /// 时长格式化:59s / 5m 12s / 1h 5m
  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  void _maybeRecordSample() {
    // 只在传输中采样;完成后不再记录,避免会话队列残留增长
    if (_info.status != TransferStatus.transferring) return;
    final now = DateTime.now();
    if (_lastSampleAt != null &&
        now.difference(_lastSampleAt!) < _sampleInterval) {
      return;
    }
    _lastSampleAt = now;
    _samples.add((time: now, bytes: transferredBytes));
    final cutoff = now.subtract(_sampleWindow);
    _samples.removeWhere((s) => s.time.isBefore(cutoff));
  }
}
