import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol_helpers.dart';
import 'socket_reader.dart';

const transferRequestTimeout = Duration(seconds: 8);
const transferMaxLine = 16 * 1024;

class TransferEntry {
  final String token;
  final String name;
  final int size;
  final String mime;
  final String path;
  final DateTime modTime;

  TransferEntry({
    required this.token,
    required this.name,
    required this.size,
    required this.mime,
    required this.path,
    required this.modTime,
  });

  Map<String, dynamic> toJson() => {
    'token': token,
    'name': name,
    'size': size,
    if (mime.isNotEmpty) 'mime': mime,
    'path': path,
    'modTime': rfc3339(modTime),
  };

  factory TransferEntry.fromJson(Map<String, dynamic> m) => TransferEntry(
    token: asString(m['token']),
    name: asString(m['name']),
    size: asInt(m['size']),
    mime: asString(m['mime']),
    path: asString(m['path']),
    modTime: parseTime(m['modTime']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class TransferServer {
  final String registryPath;
  final Map<String, TransferEntry> _files = {};
  ServerSocket? _server;
  StreamSubscription<Socket>? _sub;
  final Set<Socket> _sockets = {};
  bool _running = false;
  int _port = 0;

  void Function(String token, int sent, int total, String? error)? onProgress;
  void Function(String message)? onError;

  TransferServer(this.registryPath);

  int get port => _port;
  bool get running => _running;
  Map<String, TransferEntry> get entries =>
      Map<String, TransferEntry>.unmodifiable(_files);

  TransferEntry? entry(String token) => _files[token];

  Future<void> loadRegistry() async {
    final f = File(registryPath);
    if (!await f.exists()) return;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return;
      for (final value in raw.values) {
        if (value is! Map) continue;
        final e = TransferEntry.fromJson(Map<String, dynamic>.from(value));
        if (e.token.isEmpty || e.path.isEmpty) continue;
        if (await File(e.path).exists()) _files[e.token] = e;
      }
    } catch (_) {}
  }

  Future<void> start(int port) async {
    await stop();
    ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } catch (_) {
      if (port == 0) rethrow;
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _server = server;
    _port = server.port;
    _running = true;
    _sub = server.listen(
      _accept,
      onError: (Object e) {
        onError?.call('文件传输服务：$e');
      },
    );
  }

  void _accept(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _sockets.add(socket);
    _serve(socket).whenComplete(() {
      _sockets.remove(socket);
      try {
        socket.destroy();
      } catch (_) {}
    });
  }

  Future<void> _serve(Socket socket) async {
    final reader = SocketReader(socket);
    Map<String, dynamic>? req;
    try {
      final line = await reader
          .readLine(transferMaxLine)
          .timeout(transferRequestTimeout);
      final raw = jsonDecode(line);
      if (raw is Map) req = Map<String, dynamic>.from(raw);
    } catch (_) {
      await _writeResponse(socket, {
        'ok': false,
        'code': 'bad_request',
        'error': '请求格式错误',
      });
      return;
    }
    if (req == null) {
      await _writeResponse(socket, {
        'ok': false,
        'code': 'bad_request',
        'error': '请求格式错误',
      });
      return;
    }
    final token = asString(req['token']);
    final offset = asInt(req['offset']);
    final e = _files[token];
    if (e == null) {
      await _writeResponse(socket, {
        'ok': false,
        'code': 'not_found',
        'error': '文件不存在或发送方已重启',
      });
      return;
    }
    final file = File(e.path);
    if (!await file.exists()) {
      await _writeResponse(socket, {
        'ok': false,
        'code': 'file_missing',
        'error': '文件已被移动或删除',
      });
      return;
    }
    if (offset < 0 || offset > e.size) {
      await _writeResponse(socket, {
        'ok': false,
        'code': 'bad_offset',
        'error': '续传位置无效',
      });
      return;
    }
    try {
      await _writeResponse(socket, {
        'ok': true,
        'size': e.size,
        'name': e.name,
        if (e.mime.isNotEmpty) 'mime': e.mime,
      });
    } catch (_) {
      onProgress?.call(token, offset, e.size, 'write failed');
      return;
    }
    var done = offset;
    var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
    onProgress?.call(token, done, e.size, null);
    try {
      await for (final chunk in file.openRead(offset)) {
        socket.add(chunk);
        await socket.flush();
        done += chunk.length;
        final now = DateTime.now();
        if (done != e.size &&
            now.difference(lastReport) < const Duration(milliseconds: 100)) {
          continue;
        }
        lastReport = now;
        onProgress?.call(token, done, e.size, null);
      }
      onProgress?.call(token, done, e.size, null);
    } catch (err) {
      onProgress?.call(token, done, e.size, err.toString());
    }
  }

  Future<void> _writeResponse(Socket socket, Map<String, dynamic> resp) async {
    socket.add(utf8.encode('${jsonEncode(resp)}\n'));
    await socket.flush();
  }

  Future<TransferEntry> add(String path) async {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.directory) {
      throw StateError('is a directory');
    }
    final token = newTransferToken();
    final e = TransferEntry(
      token: token,
      name: file.uri.pathSegments.last,
      size: stat.size,
      mime: mimeOf(path),
      path: path,
      modTime: stat.modified,
    );
    _files[token] = e;
    await _save();
    return e;
  }

  Future<void> remove(String token) => removeMany([token]);

  Future<void> removeMany(List<String> tokens) async {
    var changed = false;
    for (final token in tokens) {
      if (_files.remove(token) != null) changed = true;
    }
    if (changed) await _save();
  }

  Future<void> _save() async {
    if (registryPath.isEmpty) return;
    final data = <String, dynamic>{};
    for (final entry in _files.entries) {
      data[entry.key] = entry.value.toJson();
    }
    await writeAtomic(
      registryPath,
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
  }

  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    final server = _server;
    _server = null;
    try {
      await server?.close();
    } catch (_) {}
    for (final s in _sockets.toList()) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _sockets.clear();
    _port = 0;
  }
}
