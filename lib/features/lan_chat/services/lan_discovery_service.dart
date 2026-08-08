import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/lan_device.dart';
import 'lan_chat_settings.dart';

/// UDP 广播/组播发现服务
/// 每 3 秒发送心跳广播，同时监听其他设备的心跳
class LanDiscoveryService {
  int _tcpPort = LanChatSettings.defaultChatPort;
  // 当前生效的发现端口(绑定/广播用,默认或用户手动配置)
  int _discoveryPort = LanChatSettings.defaultDiscoveryPort;
  static const Duration _heartbeatInterval = Duration(seconds: 3);

  /// 组播发现组地址:与受限广播(255.255.255.255)配合使用。
  /// 受限广播在"同一端口被多个 socket 绑定(reuseAddress)"时,
  /// 内核只把包投递给其中一个 socket,导致两台设备同时搜索时
  /// 互相收不到心跳(UI 一直转圈);组播允许多个 socket join 同一组、
  /// 各自独立收到组的包,从根上解决"两个同时搜索"的互斥问题。
  static final InternetAddress _multicastGroup = InternetAddress('239.255.0.250');

  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _offlineCheckTimer;
  bool _multicastJoined = false; // 组播加入是否已成功(失败时在心跳里重试)

  final String _deviceId;
  String _deviceName;
  bool _isRunning = false;
  String? _lastError; // 最近一次启动失败的原因(如发现端口被占用)

  final StreamController<LanDevice> _onDeviceFound = StreamController<LanDevice>.broadcast();
  final StreamController<String> _onDeviceLost = StreamController<String>.broadcast();

  Stream<LanDevice> get onDeviceFound => _onDeviceFound.stream;
  Stream<String> get onDeviceLost => _onDeviceLost.stream;
  bool get isRunning => _isRunning;
  int get tcpPort => _tcpPort;
  String get deviceId => _deviceId;
  String get deviceName => _deviceName;

  /// 最近一次启动失败的原因(如发现端口被占用),成功启动后为 null
  String? get lastError => _lastError;

  /// 同步实际 TCP 监听端口（服务器可能因端口占用回退到随机端口）
  void setTcpPort(int port) {
    if (port <= 0 || port == _tcpPort) return;
    _tcpPort = port;
    debugPrint('[LAN] TCP port updated to $port');
    // 立即广播一次，让对方尽快拿到真实端口
    if (_isRunning) _sendHeartbeat();
  }

  LanDiscoveryService({required String deviceId, String? deviceName})
      : _deviceId = deviceId,
        _deviceName = deviceName ?? 'Zebra-${Platform.localHostname}';

  void setDeviceName(String name) {
    _deviceName = name;
  }

  /// 启动发现服务，成功返回 true
  ///
  /// 绑定端口优先使用用户手动配置的发现端口,未配置时使用默认端口。
  Future<bool> start() async {
    if (_isRunning) return true;
    _isRunning = true;

    // 读取手动配置的发现端口;未配置时使用默认端口
    final port = await LanChatSettings.getDiscoveryPort() ??
        LanChatSettings.defaultDiscoveryPort;
    _discoveryPort = port;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;

      // 加入组播组:多实例/多设备可同时 join 并各自收到心跳,
      // 解决"两台同时搜索时广播只投递一个 socket"导致的转圈。
      // 部分环境(如 Android 未持 MulticastLock)不支持组播,失败不影响广播通道;
      // 失败时由心跳节拍持续重试(网络接口可能尚未就绪,重启后正常即此原因)。
      _multicastJoined = false;
      try {
        _socket!.joinMulticast(_multicastGroup);
        _multicastJoined = true;
        debugPrint('[LAN] Joined multicast group $_multicastGroup');
      } catch (e) {
        debugPrint('[LAN] Join multicast failed (广播仍可用,将重试): $e');
      }

      // 监听广播
      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleDatagram(datagram);
          }
        }
      });

      // 定期发送心跳
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());

      // 定期检查离线设备
      _offlineCheckTimer = Timer.periodic(
        _heartbeatInterval,
        (_) => _checkOffline(),
      );

      // 首次立即发送
      _sendHeartbeat();

      _lastError = null;
      debugPrint('[LAN] Discovery started on port $port');
      return true;
    } catch (e) {
      _isRunning = false;
      _lastError = '发现端口 $port 绑定失败(可能被其他程序占用):$e';
      debugPrint('[LAN] Failed to start discovery: $e');
      return false;
    }
  }

  /// 停止发现服务
  void stop() {
    _isRunning = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _offlineCheckTimer?.cancel();
    _offlineCheckTimer = null;
    _socket?.close();
    _socket = null;
    debugPrint('[LAN] Discovery stopped');
  }

  /// 发送 UDP 广播心跳
  void _sendHeartbeat() {
    if (_socket == null) return;
    try {
      // 组播加入失败时持续重试(接口未就绪/首次启动竞态),成功后即可收组播
      if (!_multicastJoined) {
        try {
          _socket!.joinMulticast(_multicastGroup);
          _multicastJoined = true;
          debugPrint('[LAN] Joined multicast group (retry) $_multicastGroup');
        } catch (_) {
          // 仍不可用,下个心跳节拍继续尝试
        }
      }
      final payload = utf8.encode(jsonEncode({
        'type': 'heartbeat',
        'deviceId': _deviceId,
        'name': _deviceName,
        'port': _tcpPort,
      }));
      // 受限广播:兼容旧版本/Android 等不支持组播的环境
      _socket!.send(
        payload,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
      // 组播:多实例同端口共存时各自都能收到(避免同时搜索互斥转圈)
      _socket!.send(
        payload,
        _multicastGroup,
        _discoveryPort,
      );
    } catch (e) {
      debugPrint('[LAN] Heartbeat send error: $e');
    }
  }

  /// 处理收到的数据报
  void _handleDatagram(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (json['type'] != 'heartbeat') return;

      final deviceId = json['deviceId'] as String?;
      if (deviceId == null || deviceId == _deviceId) return; // 忽略自己

      final device = LanDevice.fromJson(json, ip: datagram.address.address);
      _onDeviceFound.add(device);
    } catch (e) {
      // 忽略格式错误的包
    }
  }

  /// 检查离线设备（由外部 Provider 通过设备最后活跃时间判断）
  void _checkOffline() {
    // 由 Provider 维护设备列表，此处只发送事件
    // 实际离线检测在 Provider 中通过心跳超时判断
  }

  /// 发送 TCP 探测（确认设备是否在线）
  static Future<bool> probeDevice(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    stop();
    _onDeviceFound.close();
    _onDeviceLost.close();
  }
}