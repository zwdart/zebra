import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/lan_device.dart';
import '../services/lan_discovery_service.dart';

/// 局域网设备发现状态管理
class LanDiscoveryProvider extends ChangeNotifier {
  final LanDiscoveryService _discoveryService;
  final Map<String, LanDevice> _devices = {};
  final List<LanDevice> _deviceList = [];
  StreamSubscription<LanDevice>? _foundSub;
  Timer? _offlineTimer;
  bool _isRunning = false;
  String? _error;

  LanDiscoveryProvider({required String deviceId, String? deviceName})
      : _discoveryService = LanDiscoveryService(
          deviceId: deviceId,
          deviceName: deviceName,
        );

  List<LanDevice> get devices => List.unmodifiable(_deviceList);
  bool get isRunning => _isRunning;
  String? get error => _error;
  String get deviceId => _discoveryService.deviceId;
  String get deviceName => _discoveryService.deviceName;
  int get tcpPort => _discoveryService.tcpPort;

  /// 同步实际的 TCP 监听端口到心跳广播
  void setTcpPort(int port) {
    _discoveryService.setTcpPort(port);
  }

  /// 启动发现
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _error = null;
    notifyListeners();

    final ok = await _discoveryService.start();
    if (!ok) {
      _isRunning = false;
      _error = _discoveryService.lastError ?? '无法开启设备发现,请稍后重试';
      notifyListeners();
      return;
    }

    _foundSub = _discoveryService.onDeviceFound.listen(_onDeviceFound);

    // 每 10 秒检查离线设备（心跳间隔 3 秒，3 次未收到即离线）
    _offlineTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkOffline());
    notifyListeners();
  }

  /// 停止发现
  void stop() {
    _isRunning = false;
    _foundSub?.cancel();
    _foundSub = null;
    _offlineTimer?.cancel();
    _offlineTimer = null;
    _discoveryService.stop();
    notifyListeners();
  }

  /// 更新设备名
  void setDeviceName(String name) {
    if (name.trim().isEmpty) return;
    _discoveryService.setDeviceName(name.trim());
    notifyListeners();
  }

  /// 处理发现的设备
  void _onDeviceFound(LanDevice device) {
    // 以 IP+端口 作为唯一键:同一台设备(即使 deviceId 变化)只保留一条
    final key = '${device.ip}:${device.port}';
    final existing = _devices[key];
    if (existing != null) {
      // 同 IP+端口:合并,刷新在线状态、最近心跳时间与名称
      existing.isOnline = true;
      existing.lastSeen = DateTime.now();
      if (existing.name != device.name) existing.name = device.name;
      // 设备 ID 变化(旧版本未持久化 ID):以最新心跳的 ID 为准
      if (existing.id != device.id) {
        _devices.remove(key);
        _devices[key] = device;
      }
      // 每次心跳都重建排序(在线/离线分组固定、组内按 IP 序,结果幂等不跳变)
      _rebuildList();
    } else {
      // 同 ID 但 IP/端口变化(如 DHCP 换 IP):更新原条目,避免新旧两条并存
      final byIdKey = _findKeyById(device.id);
      if (byIdKey != null) {
        _devices.remove(byIdKey);
        _devices[key] = device;
      } else {
        _devices[key] = device;
      }
      _rebuildList();
    }
    notifyListeners();
  }

  /// 按设备 ID 查找已有条目在 _devices 中的键
  String? _findKeyById(String id) {
    for (final entry in _devices.entries) {
      if (entry.value.id == id) return entry.key;
    }
    return null;
  }

  /// 主动删除已发现的设备（一般用于清理离线残留条目）。
  /// 注意:若设备仍在线,收到下一次心跳后会自动重新出现。
  void removeDevice(String ip, int port) {
    _devices.remove('$ip:$port');
    _rebuildList();
    notifyListeners();
  }

  /// 检查离线设备
  void _checkOffline() {
    final now = DateTime.now();
    var changed = false;

    for (final device in _devices.values) {
      if (device.isOnline &&
          now.difference(device.lastSeen) > const Duration(seconds: 12)) {
        device.isOnline = false;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void _rebuildList() {
    _deviceList
      ..clear()
      ..addAll(_devices.values);
    _deviceList.sort((a, b) {
      // 在线/离线两段固定:在线设备优先
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      // 组内按 IP 数字序(逐段比较,避免 1.10 < 1.9 的字符串坑)
      final ipCmp = _compareIp(a.ip, b.ip);
      if (ipCmp != 0) return ipCmp;
      return a.port.compareTo(b.port);
    });
  }

  /// 按 IPv4 四段数字序比较 IP;解析失败时退化为字符串比较。
  static int _compareIp(String a, String b) {
    final pa = _parseIp(a);
    final pb = _parseIp(b);
    if (pa == null || pb == null) return a.compareTo(b);
    for (var i = 0; i < 4; i++) {
      if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
  }

  static List<int>? _parseIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      nums.add(n);
    }
    return nums;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}