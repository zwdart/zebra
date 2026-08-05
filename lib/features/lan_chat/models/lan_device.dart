/// 局域网中发现的设备信息
class LanDevice {
  final String id;
  String name;
  final String ip;
  final int port;
  DateTime lastSeen;
  bool isOnline;

  LanDevice({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 19423,
    DateTime? lastSeen,
    this.isOnline = true,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': 'heartbeat',
        'deviceId': id,
        'name': name,
        'port': port,
      };

  factory LanDevice.fromJson(Map<String, dynamic> json, {required String ip}) {
    return LanDevice(
      id: json['deviceId'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      ip: ip,
      port: json['port'] as int? ?? 19423,
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