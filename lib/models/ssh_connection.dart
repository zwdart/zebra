class SshConnection {
  final int? id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authType;
  final String? password;
  final String? privateKeyPath;
  final String? passphrase;
  final String? remark;
  final DateTime createdAt;
  final DateTime updatedAt;

  SshConnection({
    this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = 'password',
    this.password,
    this.privateKeyPath,
    this.passphrase,
    this.remark,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'auth_type': authType,
      'password': password,
      'private_key_path': privateKeyPath,
      'passphrase': passphrase,
      'remark': remark,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory SshConnection.fromMap(Map<String, dynamic> map) {
    return SshConnection(
      id: map['id'] as int?,
      name: map['name'] as String,
      host: map['host'] as String,
      port: map['port'] as int? ?? 22,
      username: map['username'] as String,
      authType: map['auth_type'] as String? ?? 'password',
      password: map['password'] as String?,
      privateKeyPath: map['private_key_path'] as String?,
      passphrase: map['passphrase'] as String?,
      remark: map['remark'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  SshConnection copyWith({
    int? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? authType,
    String? password,
    String? privateKeyPath,
    String? passphrase,
    String? remark,
  }) {
    return SshConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      password: password ?? this.password,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      passphrase: passphrase ?? this.passphrase,
      remark: remark ?? this.remark,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
