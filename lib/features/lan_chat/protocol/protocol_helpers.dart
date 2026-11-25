import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

final Random _secure = Random.secure();

String randomHex(int bytes) {
  final b = List<int>.generate(bytes, (_) => _secure.nextInt(256));
  return b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
}

String newId([String prefix = '']) {
  final id = randomHex(16);
  return prefix.isEmpty ? id : '${prefix}_$id';
}

String newHttpToken() => randomHex(16);

String newTransferToken() => 't_${randomHex(18)}';

String rfc3339(DateTime time) {
  final local = time.isUtc ? time.toLocal() : time;
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final abs = off.abs();
  final hh = abs.inHours.toString().padLeft(2, '0');
  final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
  final frac =
      local.millisecond.toString().padLeft(3, '0') +
      local.microsecond.toString().padLeft(3, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}T'
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}'
      '.$frac$sign$hh:$mm';
}

DateTime? parseTime(Object? value) {
  if (value == null) return null;
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

String humanSize(int n) {
  if (n < 1024) return '$n B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = n.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String truncateRunes(String s, int max) {
  final runes = s.runes.toList();
  if (runes.length <= max) return s;
  return '${String.fromCharCodes(runes.take(max))}…';
}

String sanitizeFileName(String name) {
  var base = p.basename(name.replaceAll('\\', '/'));
  if (base == '.' || base == '..' || base.isEmpty) base = 'file';
  final cleaned = base.replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_').trim();
  if (cleaned.isEmpty) return 'file';
  return cleaned;
}

Future<String> uniquePath(String dir, String name) async {
  final base = sanitizeFileName(name);
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot > 0 ? base.substring(dot) : '';
  var candidate = p.join(dir, base);
  var n = 1;
  while (await File(candidate).exists() ||
      await Directory(candidate).exists()) {
    candidate = p.join(dir, '$stem ($n)$ext');
    n++;
  }
  return candidate;
}

const _mimeByExt = <String, String>{
  '.txt': 'text/plain',
  '.log': 'text/plain',
  '.md': 'text/markdown',
  '.json': 'application/json',
  '.xml': 'application/xml',
  '.html': 'text/html',
  '.htm': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.pdf': 'application/pdf',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.zip': 'application/zip',
  '.gz': 'application/gzip',
  '.tar': 'application/x-tar',
  '.7z': 'application/x-7z-compressed',
  '.apk': 'application/vnd.android.package-archive',
  '.doc': 'application/msword',
  '.docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls': 'application/vnd.ms-excel',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt': 'application/vnd.ms-powerpoint',
  '.pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

String mimeOf(String path) =>
    _mimeByExt[p.extension(path).toLowerCase()] ?? 'application/octet-stream';

bool isImageMime(String mime) => mime.toLowerCase().startsWith('image/');

String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

Future<void> writeAtomic(String path, List<int> data) async {
  final dir = p.dirname(path);
  await Directory(dir).create(recursive: true);
  final tmp = File('$path.tmp-${randomHex(4)}');
  await tmp.writeAsBytes(data, flush: true);
  try {
    await tmp.rename(path);
  } catch (_) {
    final target = File(path);
    if (await target.exists()) await target.delete();
    await tmp.rename(path);
  }
}

Future<void> moveFile(String from, String to) async {
  final src = File(from);
  if (!await src.exists()) throw StateError('missing source file');
  try {
    await src.rename(to);
  } catch (_) {
    await src.copy(to);
    await src.delete();
  }
}

String? shareTokenFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final parts = uri.pathSegments;
  if (parts.length >= 2 && parts.first == 't') {
    final token = parts[1];
    if (RegExp(r'^[0-9a-fA-F]{16,64}$').hasMatch(token)) return token;
  }
  final m = RegExp(r'/t/([0-9a-fA-F]{16,64})').firstMatch(url);
  return m?.group(1);
}

String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
