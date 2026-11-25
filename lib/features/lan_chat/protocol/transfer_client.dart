import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol_helpers.dart';
import 'socket_reader.dart';
import 'transfer_server.dart';

class TransferError implements Exception {
  final String code;
  final String message;
  TransferError(this.code, this.message);
  @override
  String toString() => message;
}

class TransferResult {
  final int done;
  final int total;
  final String name;
  final String mime;
  TransferResult(this.done, this.total, this.name, this.mime);
}

class TransferClient {
  static Future<TransferResult> download({
    required String addr,
    required String token,
    required int offset,
    required FutureOr<void> Function(List<int> chunk) onData,
    void Function(int done, int total)? onProgress,
  }) async {
    if (addr.isEmpty || token.isEmpty) {
      throw StateError('missing address or token');
    }
    var host = addr;
    var port = 0;
    if (addr.contains(':')) {
      final idx = addr.lastIndexOf(':');
      host = addr.substring(0, idx);
      port = int.tryParse(addr.substring(idx + 1)) ?? 0;
    }
    if (host.isEmpty || port <= 0) {
      throw StateError('invalid transfer address');
    }
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 6),
    );
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(
        utf8.encode('${jsonEncode({'token': token, 'offset': offset})}\n'),
      );
      await socket.flush();
      final reader = SocketReader(socket);
      final line = await reader
          .readLine(transferMaxLine)
          .timeout(transferRequestTimeout);
      final raw = jsonDecode(line);
      if (raw is! Map) throw TransferError('bad_request', '无法传输文件');
      final resp = Map<String, dynamic>.from(raw);
      if (resp['ok'] != true) {
        final error = asString(resp['error'], '无法传输文件');
        throw TransferError(asString(resp['code']), error);
      }
      final total = asInt(resp['size']);
      final name = asString(resp['name']);
      final mime = asString(resp['mime']);
      var done = offset;
      if (total <= 0) throw TransferError('io_error', '文件大小无效');
      onProgress?.call(done, total);
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in reader.rest()) {
        await onData(chunk);
        done += chunk.length;
        final now = DateTime.now();
        if (done != total &&
            now.difference(last) < const Duration(milliseconds: 100)) {
          continue;
        }
        last = now;
        onProgress?.call(done, total);
      }
      onProgress?.call(done, total);
      if (done != total) {
        throw TransferError(
          'checksum_mismatch',
          'received $done of $total bytes',
        );
      }
      return TransferResult(done, total, name, mime);
    } finally {
      try {
        socket.destroy();
      } catch (_) {}
    }
  }
}
