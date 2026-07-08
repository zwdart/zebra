import 'package:flutter/material.dart';
import '../models/ssh_connection.dart';
import '../models/terminal_session.dart';
import '../services/ssh_service.dart';

class SshProvider extends ChangeNotifier {
  final SshService _sshService = SshService();
  SshConnection? _currentConnection;
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _error;

  // Terminal sessions (tabs)
  static const int maxSessions = 10;
  final List<TerminalSession> _sessions = [];
  int _activeSessionIndex = -1;
  int _tabCounter = 0;

  SshService get sshService => _sshService;
  SshConnection? get currentConnection => _currentConnection;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String? get error => _error;
  List<TerminalSession> get sessions => _sessions;
  int get activeSessionIndex => _activeSessionIndex;

  TerminalSession? get activeSession =>
      _activeSessionIndex >= 0 && _activeSessionIndex < _sessions.length
          ? _sessions[_activeSessionIndex]
          : null;

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

  // Add a new terminal tab
  Future<bool> addTerminalSession({int cols = 120, int rows = 30}) async {
    if (!_isConnected) return false;
    if (_sessions.length >= maxSessions) return false;

    _tabCounter++;
    final id = '${DateTime.now().millisecondsSinceEpoch}_$_tabCounter';
    final tabNum = _sessions.length + 1;
    final label = _currentConnection?.name ?? 'Terminal $tabNum';

    final session = TerminalSession(
      id: id,
      label: '$label ($tabNum)',
      isActive: true,
    );
    _sessions.add(session);
    _activeSessionIndex = _sessions.length - 1;
    notifyListeners();

    try {
      final terminal = await _sshService.openTerminalSession(
        id,
        cols: cols,
        rows: rows,
      );
      session.terminal = terminal;
      session.isLoading = false;
    } catch (e) {
      session.isLoading = false;
      _error = e.toString();
    }
    notifyListeners();
    return true;
  }

  // Close a terminal tab
  void closeTerminalSession(int index) {
    if (index < 0 || index >= _sessions.length) return;

    final session = _sessions[index];
    _sshService.closeTerminalSession(session.id);
    _sessions.removeAt(index);

    if (_sessions.isEmpty) {
      _activeSessionIndex = -1;
    } else if (_activeSessionIndex >= _sessions.length) {
      _activeSessionIndex = _sessions.length - 1;
    } else if (_activeSessionIndex > index) {
      _activeSessionIndex--;
    } else if (_activeSessionIndex == index) {
      _activeSessionIndex = _sessions.isEmpty ? -1 : index.clamp(0, _sessions.length - 1);
    }
    notifyListeners();
  }

  // Switch to a specific tab
  void switchSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _activeSessionIndex = index;
    notifyListeners();
  }

  void disconnect() {
    // Close all sessions
    for (final session in _sessions) {
      _sshService.closeTerminalSession(session.id);
    }
    _sessions.clear();
    _activeSessionIndex = -1;

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
