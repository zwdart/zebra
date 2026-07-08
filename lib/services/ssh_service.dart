import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

class SshService {
  SSHClient? _client;
  bool _isConnected = false;

  // Legacy single terminal support (for backward compatibility)
  Terminal? _terminal;
  SSHSession? _shellSession;

  // Multi-terminal support
  final Map<String, SSHSession> _sessions = {};
  final Map<String, Terminal> _terminals = {};

  bool get isConnected => _isConnected;
  SSHClient? get client => _client;

  final StreamController<String> _outputController = StreamController<String>.broadcast();
  Stream<String> get outputStream => _outputController.stream;

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPath,
    String? passphrase,
  }) async {
    disconnect();
    try {
      SSHSocket socket;
      try {
        socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 10));
      } catch (e) {
        throw Exception('Cannot connect to $host:$port - $e');
      }

      List<SSHKeyPair>? identities;
      if (privateKeyPath != null && privateKeyPath.isNotEmpty) {
        final keyFile = File(privateKeyPath);
        if (!keyFile.existsSync()) {
          throw Exception('Private key file not found: $privateKeyPath');
        }
        final keyPem = keyFile.readAsStringSync();
        identities = SSHKeyPair.fromPem(keyPem, passphrase?.isNotEmpty == true ? passphrase : null);
      }

      _client = SSHClient(
        socket,
        username: username,
        identities: identities,
        onPasswordRequest: password != null ? () => password : null,
        disableHostkeyVerification: true,
      );

      await _client!.authenticated;
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  // Legacy single terminal open (backward compatibility)
  Future<Terminal> openTerminal({
    int cols = 80,
    int rows = 24,
    void Function(String)? onOutput,
  }) async {
    if (_client == null) throw Exception('Not connected');

    _terminal = Terminal(
      onOutput: (data) {
        _shellSession?.write(Uint8List.fromList(utf8.encode(data)));
        onOutput?.call(data);
      },
    );

    _shellSession = await _client!.shell(
      pty: SSHPtyConfig(width: cols, height: rows),
    );

    _shellSession!.stdout.listen((data) {
      final text = utf8.decode(data, allowMalformed: true);
      _terminal?.write(text);
      _outputController.add(text);
    });

    _shellSession!.stderr.listen((data) {
      final text = utf8.decode(data, allowMalformed: true);
      _terminal?.write(text);
      _outputController.add(text);
    });

    _shellSession!.done.then((_) {
      _isConnected = false;
      _terminal?.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
    });

    return _terminal!;
  }

  // Multi-terminal: open a named terminal session
  Future<Terminal> openTerminalSession(String sessionId, {
    int cols = 80,
    int rows = 24,
  }) async {
    if (_client == null) throw Exception('Not connected');

    final terminal = Terminal(
      onOutput: (data) {
        _sessions[sessionId]?.write(Uint8List.fromList(utf8.encode(data)));
      },
    );

    final session = await _client!.shell(
      pty: SSHPtyConfig(width: cols, height: rows),
    );

    _sessions[sessionId] = session;
    _terminals[sessionId] = terminal;

    session.stdout.listen((data) {
      final text = utf8.decode(data, allowMalformed: true);
      terminal.write(text);
      _outputController.add(text);
    });

    session.stderr.listen((data) {
      final text = utf8.decode(data, allowMalformed: true);
      terminal.write(text);
      _outputController.add(text);
    });

    session.done.then((_) {
      _sessions.remove(sessionId);
      _terminals.remove(sessionId);
      terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
    });

    return terminal;
  }

  // Multi-terminal: close a specific session
  void closeTerminalSession(String sessionId) {
    _sessions[sessionId]?.close();
    _sessions.remove(sessionId);
    _terminals.remove(sessionId);
  }

  // Multi-terminal: get terminal by session id
  Terminal? getTerminalSession(String sessionId) => _terminals[sessionId];

  // Multi-terminal: resize a specific session
  void resizeTerminalSession(String sessionId, int cols, int rows) {
    _sessions[sessionId]?.resizeTerminal(cols, rows, 0, 0);
  }

  void sendInput(String input) {
    _shellSession?.write(Uint8List.fromList(utf8.encode(input)));
  }

  void resizeTerminal(int cols, int rows) {
    _shellSession?.resizeTerminal(cols, rows, 0, 0);
  }

  Future<SftpClient> sftp() async {
    if (_client == null) throw Exception('Not connected');
    return _client!.sftp();
  }

  Future<String> execute(String command) async {
    if (_client == null) throw Exception('Not connected');
    final session = await _client!.execute(command);
    final output = await session.stdout
        .map((data) => utf8.decode(data, allowMalformed: true))
        .join();
    await session.done;
    return output;
  }

  void disconnect() {
    // Close all terminal sessions
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
    _terminals.clear();

    // Legacy
    _shellSession?.close();
    _client?.close();
    _client = null;
    _shellSession = null;
    _terminal = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _outputController.close();
  }
}
