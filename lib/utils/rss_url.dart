/// RSS URL 归一化工具。
///
/// 目的:消除同一订阅源因书写差异产生的"同源双记录"——
/// 例如 `https://X.com/feed/` 与 `http://x.com/feed` 实为同一源。
/// 归一化规则:
///   - 去除首尾空白
///   - 去除末尾斜杠(根路径除外)
///   - scheme 统一(http/https 均视为 https),host 转小写
///   - 去除默认端口(80/443)
String normalizeRssUrl(String url) {
  var u = url.trim();
  if (u.isEmpty) return u;

  // 末尾斜杠:仅当还有内容时去掉(保留 "https://host/" 的根形式)
  while (u.length > 1 && u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }

  final uri = Uri.tryParse(u);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return u;

  // http/https 视为同一协议(http-only 源仍可被服务器/客户端抓取,匹配不受影响)
  final scheme = uri.scheme.toLowerCase();
  final normalizedScheme = (scheme == 'http' || scheme == 'https') ? 'https' : scheme;
  final host = uri.host.toLowerCase();
  final port = uri.hasPort && uri.port != 80 && uri.port != 443 ? ':${uri.port}' : '';
  final path = uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '$normalizedScheme://$host$port$path$query';
}
