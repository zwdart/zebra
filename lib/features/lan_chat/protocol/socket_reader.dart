import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class SocketReader {
  final StreamIterator<Uint8List> _it;
  final List<int> _buffer = [];

  SocketReader(Stream<Uint8List> stream)
    : _it = StreamIterator<Uint8List>(stream);

  bool get hasBuffered => _buffer.isNotEmpty;

  Future<String> readLine(int maxBytes) async {
    while (true) {
      final idx = _buffer.indexOf(10);
      if (idx >= 0) {
        final lineBytes = _buffer.sublist(0, idx);
        _buffer.removeRange(0, idx + 1);
        var end = lineBytes.length;
        if (end > 0 && lineBytes[end - 1] == 13) end--;
        return utf8.decode(lineBytes.sublist(0, end), allowMalformed: true);
      }
      if (_buffer.length > maxBytes) {
        throw const FormatException('line is too large');
      }
      final hasNext = await _it.moveNext();
      if (!hasNext) {
        if (_buffer.isEmpty) {
          throw const LineReaderException('connection closed');
        }
        final lineBytes = List<int>.from(_buffer);
        _buffer.clear();
        var end = lineBytes.length;
        if (end > 0 && lineBytes[end - 1] == 13) end--;
        return utf8.decode(lineBytes.sublist(0, end), allowMalformed: true);
      }
      _buffer.addAll(_it.current);
      if (_buffer.length > maxBytes && !_buffer.contains(10)) {
        throw const FormatException('line is too large');
      }
    }
  }

  Stream<Uint8List> rest() async* {
    if (_buffer.isNotEmpty) {
      yield Uint8List.fromList(List<int>.from(_buffer));
      _buffer.clear();
    }
    while (await _it.moveNext()) {
      yield _it.current;
    }
  }

  Future<void> cancel() => _it.cancel();
}

class LineReaderException implements Exception {
  final String message;
  const LineReaderException(this.message);
  @override
  String toString() => message;
}
