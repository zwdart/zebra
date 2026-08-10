import '../services/lan_chat_settings.dart';
import 'room.dart';

/// 局域网中发现的设备信息
class LanDevice {
  final String id;
  String name;
  final String ip;
  final int port;
  DateTime lastSeen;
  bool isOnline;
  /// 该设备正在主持的房间(心跳 room 摘要);非房主为 null
  RoomInfo? roomInfo;

  LanDevice({
    required this.id,
    required this.name,
    required this.ip,
    this.port = LanChatSettings.defaultChatPort,
    DateTime? lastSeen,
    this.isOnline = true,
    this.roomInfo,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': 'heartbeat',
        'deviceId': id,
        'name': name,
        'port': port,
        if (roomInfo != null) 'room': roomInfo!.toJson(),
      };

  factory LanDevice.fromJson(Map<String, dynamic> json, {required String ip}) {
    return LanDevice(
      id: json['deviceId'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      ip: ip,
      port: json['port'] as int? ?? LanChatSettings.defaultChatPort,
      roomInfo: json['room'] is Map<String, dynamic>
          ? RoomInfo.fromJson(json['room'] as Map<String, dynamic>)
          : null,
    );
  }

  LanDevice copyWith({bool? isOnline, DateTime? lastSeen}) {
    return LanDevice(
      id: id,
      name: name,
      ip: ip,
      port: port,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LanDevice && id == other.id;

  @override
  int get hashCode => id.hashCode;
}