import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'protocol_helpers.dart';

const maxUploadSize = 8 * 1024 * 1024 * 1024;

class HttpTransfer {
  final String token;
  final String path;
  final String name;
  final int size;
  final String mime;
  final DateTime created;

  HttpTransfer({
    required this.token,
    required this.path,
    required this.name,
    required this.size,
    required this.mime,
    required this.created,
  });

  Map<String, dynamic> toJson() => {
    'token': token,
    'path': path,
    'name': name,
    'size': size,
    'mime': mime,
    'created': rfc3339(created),
  };

  factory HttpTransfer.fromJson(Map<String, dynamic> m) => HttpTransfer(
    token: asString(m['token']),
    path: asString(m['path']),
    name: asString(m['name']),
    size: asInt(m['size']),
    mime: asString(m['mime']),
    created: parseTime(m['created']) ?? DateTime.now(),
  );
}

class ShareServer {
  final String persist;
  final Map<String, HttpTransfer> _transfers = {};
  String dir = '';
  String uploadDir = '';
  int _port = 0;
  HttpServer? _server;
  bool _running = false;
  bool english = false;

  void Function(String token, int sent, int total, String? error)? onProgress;
  void Function(String message)? onError;

  ShareServer(this.persist);

  bool get running => _running;
  int get port => _port;

  String _t(String zh, String en) => english ? en : zh;

  Future<void> loadTransfers() async {
    final file = File(persist);
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final tr = HttpTransfer.fromJson(Map<String, dynamic>.from(item));
        if (tr.token.isEmpty || tr.path.isEmpty) continue;
        if (await File(tr.path).exists()) _transfers[tr.token] = tr;
      }
    } catch (_) {}
  }

  Future<void> _saveTransfers() async {
    if (persist.isEmpty) return;
    final list = _transfers.values.toList()
      ..sort((a, b) => a.created.compareTo(b.created));
    await writeAtomic(
      persist,
      utf8.encode(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(list.map((e) => e.toJson()).toList()),
      ),
    );
  }

  Future<void> start(int port) async {
    await stop();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    _port = server.port;
    _running = true;
    server.listen(
      (request) {
        _handle(request).catchError((Object e) {
          onError?.call('HTTP 请求失败：$e');
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('error');
            request.response.close();
          } catch (_) {}
        });
      },
      onError: (Object e) {
        onError?.call('HTTP 服务：$e');
      },
    );
  }

  Future<void> stop() async {
    _running = false;
    final server = _server;
    _server = null;
    _port = 0;
    try {
      await server?.close(force: true);
    } catch (_) {}
  }

  String? primaryHost(List<String> ips) {
    for (final ip in ips) {
      if (!ip.startsWith('127.') && !ip.startsWith('169.254.')) return ip;
    }
    return ips.isEmpty ? null : ips.first;
  }

  List<String> urls(List<String> ips) {
    if (_port == 0) return [];
    return ips.map((ip) => 'http://$ip:$_port/').toList();
  }

  String transferUrl(String? host, HttpTransfer tr, List<String> ips) {
    final h = (host == null || host.isEmpty) ? primaryHost(ips) : host;
    if (h == null || _port == 0) return '';
    final name = Uri.encodeComponent(tr.name);
    return 'http://$h:$_port/t/${tr.token}/$name';
  }

  HttpTransfer? transferFor(String token) => _transfers[token];

  Future<HttpTransfer> addTransfer(String path) async {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.directory) {
      throw StateError('a directory cannot be an attachment');
    }
    final tr = HttpTransfer(
      token: newHttpToken(),
      path: path,
      name: p.basename(path),
      size: stat.size,
      mime: mimeOf(path),
      created: DateTime.now(),
    );
    _transfers[tr.token] = tr;
    await _saveTransfers();
    return tr;
  }

  Future<void> removeTransfer(String token) async {
    if (_transfers.remove(token) != null) {
      await _saveTransfers();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('X-Content-Type-Options', 'nosniff');
    final segments = request.uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 't') {
      await _serveTransfer(request, segments);
      return;
    }
    if (request.uri.path == '/health') {
      response.headers.contentType = ContentType(
        'text',
        'plain',
        charset: 'utf-8',
      );
      response.write('zchat\n');
      await response.close();
      return;
    }
    if (request.uri.path == '/upload') {
      await _serveUpload(request);
      return;
    }
    await _serveDir(request, segments);
  }

  int? _parseSize(String? header, int size) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final spec = header.substring(6);
    if (spec.contains(',')) return null;
    final dash = spec.indexOf('-');
    if (dash < 0) return null;
    final a = spec.substring(0, dash).trim();
    final b = spec.substring(dash + 1).trim();
    if (a.isEmpty) {
      final suffix = int.tryParse(b);
      if (suffix == null || suffix <= 0) return -1;
      if (suffix >= size) return 0;
      return size - suffix;
    }
    final start = int.tryParse(a);
    if (start == null || start < 0) return -1;
    if (start >= size) return -1;
    return start;
  }

  Future<void> _serveTransfer(
    HttpRequest request,
    List<String> segments,
  ) async {
    final response = request.response;
    if (segments.length < 2) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final token = segments[1];
    final tr = _transfers[token];
    if (tr == null) {
      response.headers.set('X-Zchat-Error-Code', 'not_found');
      response.statusCode = HttpStatus.notFound;
      response.write('not found');
      await response.close();
      return;
    }
    final file = File(tr.path);
    if (!await file.exists()) {
      response.headers.set('X-Zchat-Error-Code', 'file_missing');
      response.statusCode = HttpStatus.notFound;
      response.write(_t('文件已不存在', 'File no longer exists'));
      await response.close();
      return;
    }
    await _serveFile(
      request,
      file,
      displayName: tr.name,
      mime: tr.mime,
      modTime: tr.created,
      progressToken: token,
    );
  }

  Future<void> _serveFile(
    HttpRequest request,
    File file, {
    required String displayName,
    required String mime,
    required DateTime modTime,
    String? progressToken,
  }) async {
    final response = request.response;
    final size = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = size - 1;
    var partial = false;
    if (rangeHeader != null &&
        (request.method == 'GET' || request.method == 'HEAD')) {
      final parsed = _parseSize(rangeHeader, size);
      if (parsed == -1) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await response.close();
        return;
      }
      if (parsed != null) {
        start = parsed;
        partial = true;
      }
    }
    if (size == 0) end = -1;
    final length = end >= start ? end - start + 1 : 0;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(
      HttpHeaders.lastModifiedHeader,
      HttpDate.format(modTime),
    );
    if (mime.isNotEmpty) {
      response.headers.contentType = ContentType.parse(mime);
    }
    if (request.uri.queryParameters['download'] == '1') {
      final encoded = Uri.encodeComponent(displayName);
      response.headers.set(
        'Content-Disposition',
        "attachment; filename*=UTF-8''$encoded",
      );
    }
    if (partial) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    } else {
      response.statusCode = HttpStatus.ok;
    }
    response.contentLength = length;
    if (request.method == 'HEAD') {
      await response.close();
      if (progressToken != null && length == 0) {
        onProgress?.call(progressToken, 0, size, null);
      }
      return;
    }
    if (length == 0) {
      await response.close();
      onProgress?.call(progressToken ?? '', 0, size, null);
      return;
    }
    var done = start;
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    if (progressToken != null) {
      onProgress?.call(progressToken, done, size, null);
    }
    try {
      await for (final chunk in file.openRead(start, end + 1)) {
        response.add(chunk);
        await response.flush();
        done += chunk.length;
        final now = DateTime.now();
        if (progressToken != null &&
            (done >= size ||
                now.difference(last) >= const Duration(milliseconds: 150))) {
          last = now;
          onProgress?.call(progressToken, done, size, null);
        }
      }
      await response.close();
      if (progressToken != null) {
        onProgress?.call(progressToken, size, size, null);
      }
    } catch (e) {
      if (progressToken != null) {
        onProgress?.call(progressToken, done, size, e.toString());
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveDir(HttpRequest request, List<String> segments) async {
    final response = request.response;
    final uploadEnabled = await _uploadEnabled();
    if (dir.isEmpty) {
      response.headers.contentType = ContentType(
        'text',
        'html',
        charset: 'utf-8',
      );
      response.write(
        _page(
          title: _t('Zebra 文件共享', 'Zebra File Share'),
          body: uploadEnabled
              ? '<p>${_esc(_t('共享目录未设置，但可以上传文件', 'No share directory set, but uploads are allowed'))}</p>${_uploadForm('/')}'
              : '<p>${_esc(_t('这个服务正在运行，但还没有选择共享目录。', 'The service is running, but no share directory is selected.'))}</p>',
        ),
      );
      await response.close();
      return;
    }
    String? full;
    try {
      full = await _safeJoin(dir, segments);
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
      response.write(_t('无效的路径', 'Invalid path'));
      await response.close();
      return;
    }
    final entity = FileSystemEntity.typeSync(full);
    if (entity == FileSystemEntityType.notFound) {
      response.statusCode = HttpStatus.notFound;
      response.write('not found');
      await response.close();
      return;
    }
    if (entity == FileSystemEntityType.file) {
      final stat = await File(full).stat();
      final name = p.basename(full);
      await _serveFile(
        request,
        File(full),
        displayName: name,
        mime: mimeOf(full),
        modTime: stat.modified,
      );
      return;
    }
    if (entity != FileSystemEntityType.directory) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final query = request.uri.queryParameters['q']?.trim() ?? '';
    final entries = <_DirEntry>[];
    await for (final e in Directory(full).list(followLinks: false)) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (query.isNotEmpty &&
          !name.toLowerCase().contains(query.toLowerCase())) {
        continue;
      }
      final stat = await e.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      final rel = segments.where((s) => s.isNotEmpty).toList()..add(name);
      final href =
          '/${rel.map(Uri.encodeComponent).join('/')}${isDir ? '/' : ''}';
      entries.add(
        _DirEntry(
          name: name,
          href: href,
          isDir: isDir,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    final relParts = segments.where((s) => s.isNotEmpty).toList();
    final parent = relParts.isEmpty
        ? ''
        : (relParts.length == 1
              ? '/'
              : '/${relParts.sublist(0, relParts.length - 1).map(Uri.encodeComponent).join('/')}/');
    final title = relParts.isEmpty
        ? _t('共享目录', 'Shared Folder')
        : relParts.last;
    final uploaded =
        int.tryParse(request.uri.queryParameters['uploaded'] ?? '') ?? 0;
    final notice = uploaded > 0
        ? '<div class="notice">${_esc(_t('已上传 $uploaded 个文件', '$uploaded file(s) uploaded'))}</div>'
        : '';
    final count = query.isNotEmpty
        ? _t(
            '搜索 “$query” · ${entries.length} 个结果',
            'Search "$query" · ${entries.length} result(s)',
          )
        : _t('${entries.length} 个文件', '${entries.length} file(s)');
    final sb = StringBuffer();
    sb.write(
      '<div class="search"><form method="get" action="/">'
      '<input name="q" value="${_esc(query)}" placeholder="${_esc(_t('在共享目录中搜索', 'Search shared folder'))}" aria-label="${_esc(_t('搜索', 'Search'))}">'
      '<button type="submit">${_esc(_t('搜索', 'Search'))}</button></form></div>',
    );
    sb.write('<div class="count">${_esc(count)}</div>');
    sb.write(notice);
    if (parent.isNotEmpty) {
      sb.write(
        '<div class="card"><a class="row" href="${_esc(parent)}">'
        '<span class="ico">↑</span><span class="name">${_esc(_t('返回上一级', 'Parent folder'))}</span></a></div>',
      );
    }
    sb.write('<div class="card">');
    if (entries.isEmpty) {
      sb.write(
        '<div class="empty">${_esc(_t('这个目录是空的', 'This folder is empty'))}</div>',
      );
    } else {
      for (final e in entries) {
        final ago = e.modified;
        final date =
            '${ago.year}-${ago.month.toString().padLeft(2, '0')}-'
            '${ago.day.toString().padLeft(2, '0')} '
            '${ago.hour.toString().padLeft(2, '0')}:'
            '${ago.minute.toString().padLeft(2, '0')}';
        sb.write(
          '<a class="row" href="${_esc(e.href)}">'
          '<span class="ico">${e.isDir ? '📁' : '📄'}</span>'
          '<span class="name">${_esc(e.name)}</span>'
          '<span class="meta">${_esc(e.isDir ? _t('文件夹', 'Folder') : humanSize(e.size))}<br>${_esc(date)}</span>'
          '</a>',
        );
      }
    }
    sb.write('</div>');
    if (uploadEnabled) sb.write(_uploadForm(request.uri.path));
    final footer = uploadEnabled
        ? _t('由 Zebra 在局域网共享 · 可上传', 'Shared by Zebra on LAN · Upload allowed')
        : _t('由 Zebra 在局域网共享 · 只读', 'Shared by Zebra on LAN · Read only');
    sb.write('<footer>${_esc(footer)}</footer>');
    response.headers.contentType = ContentType(
      'text',
      'html',
      charset: 'utf-8',
    );
    response.write(_page(title: title, body: sb.toString()));
    await response.close();
  }

  Future<bool> _uploadEnabled() async {
    if (uploadDir.isEmpty) return false;
    final stat = await Directory(uploadDir).stat();
    return stat.type == FileSystemEntityType.directory;
  }

  String _uploadForm(String next) {
    return '<form class="upload" method="post" action="/upload" enctype="multipart/form-data">'
        '<input type="hidden" name="next" value="${_esc(next)}">'
        '<div class="uploadHint">${_esc(_t('选择文件后上传到共享者的上传目录', 'Choose files to upload to the host upload folder'))}</div>'
        '<input type="file" name="files" multiple required>'
        '<button type="submit">${_esc(_t('上传', 'Upload'))}</button></form>';
  }

  Future<void> _serveUpload(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'POST') {
      response.headers.set(HttpHeaders.allowHeader, 'POST');
      response.statusCode = HttpStatus.methodNotAllowed;
      response.write(_t('请求格式错误', 'Bad request'));
      await response.close();
      return;
    }
    if (!await _uploadEnabled()) {
      response.statusCode = HttpStatus.forbidden;
      response.write(_t('未开启上传', 'Upload disabled'));
      await response.close();
      return;
    }
    if (request.contentLength > maxUploadSize) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      response.write(_t('文件过大', 'File too large'));
      await response.close();
      return;
    }
    final contentType = request.headers.contentType;
    final boundary = contentType?.parameters['boundary'];
    if (contentType == null ||
        contentType.mimeType != 'multipart/form-data' ||
        boundary == null ||
        boundary.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      response.write(_t('请求格式错误', 'Bad request'));
      await response.close();
      return;
    }
    var next = '/';
    final saved = <String>[];
    var total = 0;
    try {
      final transformer = MimeMultipartTransformer(boundary);
      final parts = request
          .map<List<int>>((chunk) => chunk)
          .transform(transformer);
      await for (final part in parts) {
        final disposition = part.headers['content-disposition'] ?? '';
        final name = _dispositionValue(disposition, 'filename');
        if (name.isEmpty) {
          final formName = _dispositionValue(disposition, 'name');
          if (formName == 'next') {
            final bytes = <int>[];
            await for (final chunk in part) {
              bytes.addAll(chunk);
              if (bytes.length >= 2048) break;
            }
            next = _cleanUploadNext(utf8.decode(bytes, allowMalformed: true));
          }
          continue;
        }
        var uploadName = sanitizeFileName(name);
        if (uploadName == 'file') uploadName = 'upload';
        uploadName = truncateRunes(uploadName, 120);
        final dest = await uniquePath(uploadDir, uploadName);
        final sink = File(dest).openWrite();
        try {
          await for (final chunk in part) {
            total += chunk.length;
            if (total > maxUploadSize) throw const _TooLarge();
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }
        saved.add(dest);
      }
    } on _TooLarge {
      for (final f in saved) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
      response.statusCode = HttpStatus.requestEntityTooLarge;
      response.write(_t('文件过大', 'File too large'));
      await response.close();
      return;
    } catch (_) {
      for (final f in saved) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
      response.statusCode = HttpStatus.badRequest;
      response.write(_t('请求格式错误', 'Bad request'));
      await response.close();
      return;
    }
    if (saved.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      response.write(_t('没有选择文件', 'No file selected'));
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.seeOther;
    final location = Uri.parse(
      next,
    ).replace(queryParameters: {'uploaded': saved.length.toString()});
    response.headers.set(HttpHeaders.locationHeader, location.toString());
    await response.close();
  }

  String _dispositionValue(String disposition, String key) {
    final re = RegExp(
      '$key\\*?=(?:"((?:\\\\.|[^"])*)"|([^;]*))',
      caseSensitive: false,
    );
    final m = re.firstMatch(disposition);
    if (m == null) return '';
    var value = m.group(1) ?? m.group(2) ?? '';
    value = value.trim();
    if (value.toLowerCase().startsWith("utf-8''")) {
      value = Uri.decodeComponent(value.substring(7));
    } else if (m.group(1) != null) {
      value = value.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
    }
    return value;
  }

  String _cleanUploadNext(String next) {
    var value = next.trim();
    if (value.isEmpty || !value.startsWith('/') || value.startsWith('//')) {
      return '/';
    }
    try {
      final uri = Uri.parse(value);
      if (uri.hasScheme || uri.host.isNotEmpty) return '/';
      final path = uri.path;
      if (path.isEmpty || path == '/upload' || path.startsWith('//')) {
        return '/';
      }
      return path;
    } catch (_) {
      return '/';
    }
  }

  String _page({required String title, required String body}) {
    final lang = english ? 'en' : 'zh-CN';
    return '''<!doctype html>
<html lang="$lang"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${_esc(title)} · Zebra</title>
<style>
:root{color-scheme:light dark}
*{box-sizing:border-box}
body{margin:0;padding:24px 16px 40px;background:#f3f3f7;color:#1d1d1f;
font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif}
main{max-width:720px;margin:0 auto}
h1{font-size:24px;line-height:1.2;margin:0 0 16px;overflow-wrap:anywhere}
.search{display:flex;gap:8px;margin-bottom:10px}
.search input{flex:1;min-width:0;border:1px solid #d5d5dc;border-radius:10px;
padding:10px 12px;font:inherit;background:#fff;color:inherit}
.search button,.upload button{border:0;border-radius:10px;background:#3b6ef5;
color:#fff;font:inherit;font-weight:600;padding:10px 16px}
.count{color:#6b6b73;font-size:14px;margin:0 4px 12px}
.notice{background:#e6f0ff;color:#1d4fbf;border-radius:10px;padding:10px 12px;margin-bottom:12px}
.card{background:#fff;border-radius:14px;overflow:hidden;margin-bottom:14px;
box-shadow:0 1px 2px rgba(0,0,0,.06)}
.row{display:flex;align-items:center;gap:12px;padding:13px 14px;color:inherit;
text-decoration:none;border-bottom:1px solid #ededf2}
.row:last-child{border-bottom:0}
.ico{width:26px;text-align:center;font-size:20px}
.name{flex:1;min-width:0;overflow-wrap:anywhere}
.meta{color:#787880;font-size:12px;white-space:nowrap;text-align:right}
.empty{padding:28px;text-align:center;color:#8a8a92}
.upload{margin:0 0 18px}
.uploadHint{color:#6b6b73;font-size:14px;margin:0 4px 10px}
.upload input{display:block;width:100%;background:#fff;border:1px dashed #c9c9d2;
border-radius:12px;padding:14px;font:inherit;margin-bottom:10px}
footer{color:#8a8a92;font-size:12px;text-align:center;margin-top:24px}
@media(prefers-color-scheme:dark){
body{background:#141416;color:#f5f5f7}
.card,.search input,.upload input{background:#232327;border-color:#3a3a40}
.row{border-color:#303036}.count,.uploadHint,footer{color:#a1a1aa}
.notice{background:#1e2a44;color:#a9c4ff}
}
</style></head><body><main><h1>${_esc(title)}</h1>$body</main></body></html>''';
  }

  String _esc(String s) => const HtmlEscape().convert(s);
}

class _DirEntry {
  final String name;
  final String href;
  final bool isDir;
  final int size;
  final DateTime modified;
  _DirEntry({
    required this.name,
    required this.href,
    required this.isDir,
    required this.size,
    required this.modified,
  });
}

class _TooLarge implements Exception {
  const _TooLarge();
}

Future<String> _safeJoin(String root, List<String> segments) async {
  var canonicalRoot = p.normalize(p.absolute(root));
  try {
    canonicalRoot = await Directory(root).resolveSymbolicLinks();
  } catch (_) {}
  var full = canonicalRoot;
  for (final seg in segments) {
    if (seg.isEmpty) continue;
    if (seg == '.' || seg == '..' || seg.contains('\x00')) {
      throw StateError('invalid path');
    }
    full = p.join(full, seg);
  }
  full = p.normalize(full);
  if (full != canonicalRoot &&
      !full.startsWith('$canonicalRoot${p.separator}')) {
    throw StateError('invalid path');
  }
  final type = FileSystemEntity.typeSync(full);
  if (type != FileSystemEntityType.notFound) {
    try {
      final real = type == FileSystemEntityType.directory
          ? await Directory(full).resolveSymbolicLinks()
          : await File(full).resolveSymbolicLinks();
      if (real != canonicalRoot &&
          !real.startsWith('$canonicalRoot${p.separator}')) {
        throw StateError('invalid path');
      }
      return real;
    } catch (_) {}
  }
  return full;
}
