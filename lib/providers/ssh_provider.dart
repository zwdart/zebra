import 'package:flutter/material.dart';
import '../models/ssh_connection.dart';
import '../services/ssh_service.dart';

class SshProvider extends ChangeNotifier {
  final SshService _sshService = SshService();
  SshConnection? _currentConnection;
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _error;

  SshService get sshService => _sshService;
  SshConnection? get currentConnection => _currentConnection;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String? get error => _error;

  Future<void> connect(SshConnection conn) async {
    _isConnecting = true;
    _error = null;
    _currentConnection = conn;
    notifyListeners();

    try {
      await _sshService.connect(
        host: conn.host,
        port: conn.port,
        username: conn.username,
        password: conn.authType == 'password' ? conn.password : null,
        privateKeyPath: conn.authType == 'key' ? conn.privateKeyPath : null,
        passphrase: conn.passphrase,
      );
      _isConnected = true;
      _isConnecting = false;
    } catch (e) {
      _error = e.toString();
      _isConnected = false;
      _isConnecting = false;
    }
    notifyListeners();
  }

  void disconnect() {
    _sshService.disconnect();
    _isConnected = false;
    _currentConnection = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sshService.dispose();
    super.dispose();
  }
}
