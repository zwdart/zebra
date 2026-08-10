/// 房间信息(心跳广播与附近房间列表展示用)
class RoomInfo {
  final String roomId;
  final String name;
  final String hostName;
  final int port; // 房主 RoomHost 实际监听端口
  final int memberCount;

  RoomInfo({
    required this.roomId,
    required this.name,
    required this.hostName,
    required this.port,
    this.memberCount = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': roomId,
        'name': name,
        'hostName': hostName,
        'port': port,
        'memberCount': memberCount,
      };

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      roomId: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      hostName: json['hostName'] as String? ?? '',
      port: json['port'] as int? ?? 0,
      memberCount: json['memberCount'] as int? ?? 1,
    );
  }
}

/// 房间成员(房主侧持有 socket,成员侧仅展示信息)
class RoomMember {
  final String deviceId;
  final String deviceName;
  final DateTime joinedAt;

  RoomMember({
    required this.deviceId,
    required this.deviceName,
    DateTime? joinedAt,
  }) : joinedAt = joinedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
      };

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? '',
    );
  }

  RoomMember copyWith({String? deviceName}) {
    return RoomMember(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      joinedAt: joinedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RoomMember && deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}
