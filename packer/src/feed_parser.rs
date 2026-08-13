// ============================================================
// 轻量 RSS/Atom Feed 解析器（手写，无三方 XML 库）
// 支持 rss1 / rss2 / atom 三种格式，自动检测
// ============================================================

/// 解析出的一篇文章
#[derive(Debug, Clone, Default)]
pub struct FeedArticle {
    pub guid: String,
    pub title: String,
    pub link: String,
    pub author: String,
    pub summary: String,
    pub content: String,
    pub published_at: Option<String>,
}

/// 解析 Feed 正文，返回文章列表（按出现顺序）
pub fn parse_feed(body: &str, feed_type: &str) -> Vec<FeedArticle> {
    // 自动检测格式
    let actual = if feed_type.is_empty() {
        detect_feed_type(body)
    } else {
        feed_type
    };

    match actual {
        "atom" => parse_atom(body),
        "rss1" => parse_rss1(body),
        _ => parse_rss2(body),
    }
}

/// 根据根标签检测格式
pub fn detect_feed_type(body: &str) -> &'static str {
    let head = &body[..body.len().min(500)];
    if head.contains("<feed") {
        "atom"
    } else if head.contains("rdf:RDF") || head.contains("RDF xmlns") {
        "rss1"
    } else {
        "rss2"
    }
}

// ============================================================
// 通用工具：提取标签文本 / 属性
// ============================================================

/// 提取第一个指定标签的 inner text（支持 CDATA、自闭合、大小写不敏感）
fn tag_text(xml: &str, tag: &str) -> Option<String> {
    let lower = xml.to_lowercase();
    let open = format!("<{}", tag.to_lowercase());
    let mut search_from = 0;
    while let Some(start) = lower[search_from..].find(&open) {
        let abs_start = search_from + start;
        // 确认是完整标签名（避免 <title> 匹配 <titlefoo>）
        let after = lower[abs_start + open.len()..].chars().next();
        if let Some(c) = after {
            if c.is_alphanumeric() || c == ':' || c == '-' || c == '_' {
                search_from = abs_start + open.len();
                continue;
            }
        }
        // 找到标签开始，找 '>' 结束
        let gt = match lower[abs_start..].find('>') {
            Some(i) => abs_start + i,
            None => return None,
        };
        // 自闭合标签 <tag ... /> → 空文本
        if lower[..gt].ends_with('/') {
            return Some(String::new());
        }
        // 找对应闭合标签 </tag ...>
        let close = format!("</{}", tag.to_lowercase());
        if let Some(rel) = lower[gt..].find(&close) {
            let end = gt + rel;
            let raw = &xml[gt + 1..end];
            return Some(clean_text(raw));
        }
        search_from = gt + 1;
    }
    None
}

/// 提取某标签内嵌套子标签文本，例如 <author><name>X</name></author> 取 name
fn child_text(xml: &str, parent: &str, child: &str) -> Option<String> {
    let lower = xml.to_lowercase();
    let open = format!("<{}", parent.to_lowercase());
    if let Some(start) = lower.find(&open) {
        let gt = lower[start..].find('>').map(|i| start + i)?;
        let close = format!("</{}", parent.to_lowercase());
        let end = lower[gt..].find(&close).map(|i| gt + i)?;
        let inner = &xml[gt + 1..end];
        return tag_text(inner, child);
    }
    None
}

/// 提取第一个 href 属性值
fn attr_href(tag: &str) -> Option<String> {
    for (pat, close) in [("href=\"", '"'), ("href='", '\'')] {
        if let Some(start) = tag.find(pat) {
            let val_start = start + pat.len();
            let rest = &tag[val_start..];
            if let Some(end) = rest.find(close) {
                return Some(rest[..end].to_string());
            }
        }
    }
    None
}

/// 清理文本：去 CDATA、HTML 实体解码、折叠空白
fn clean_text(raw: &str) -> String {
    let mut s = raw.trim().to_string();
    // CDATA
    if s.starts_with("<![CDATA[") && s.ends_with("]]>") {
        s = s[9..s.len() - 3].to_string();
    }
    // 基本实体解码
    s = s
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
        .replace("&#39;", "'")
        .replace("&#34;", "\"");
    // 折叠空白（正文保留换行，仅压缩多余空白）
    s.lines()
        .map(|l| l.trim())
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string()
}

// ============================================================
// RSS 2.0
// ============================================================

fn parse_rss2(body: &str) -> Vec<FeedArticle> {
    extract_blocks(body, "item")
        .into_iter()
        .map(|block| FeedArticle {
            guid: tag_text(&block, "guid")
                .or_else(|| tag_text(&block, "link"))
                .unwrap_or_default(),
            title: tag_text(&block, "title").unwrap_or_default(),
            link: tag_text(&block, "link").unwrap_or_default(),
            author: tag_text(&block, "dc:creator")
                .or_else(|| tag_text(&block, "author"))
                .unwrap_or_default(),
            summary: tag_text(&block, "description").unwrap_or_default(),
            content: tag_text(&block, "content:encoded")
                .or_else(|| tag_text(&block, "description"))
                .unwrap_or_default(),
            published_at: tag_text(&block, "pubDate")
                .or_else(|| tag_text(&block, "dc:date"))
                .or_else(|| tag_text(&block, "date")),
        })
        .collect()
}

// ============================================================
// RSS 1.0（RDF）
// ============================================================

fn parse_rss1(body: &str) -> Vec<FeedArticle> {
    extract_blocks(body, "item")
        .into_iter()
        .map(|block| FeedArticle {
            guid: tag_text(&block, "rdf:about")
                .or_else(|| tag_text(&block, "guid"))
                .unwrap_or_default(),
            title: tag_text(&block, "title").unwrap_or_default(),
            link: tag_text(&block, "link").unwrap_or_default(),
            author: tag_text(&block, "dc:creator").unwrap_or_default(),
            summary: tag_text(&block, "description").unwrap_or_default(),
            content: tag_text(&block, "content:encoded")
                .or_else(|| tag_text(&block, "description"))
                .unwrap_or_default(),
            published_at: tag_text(&block, "dc:date"),
        })
        .collect()
}

// ============================================================
// Atom
// ============================================================

fn parse_atom(body: &str) -> Vec<FeedArticle> {
    extract_blocks(body, "entry")
        .into_iter()
        .map(|block| FeedArticle {
            guid: tag_text(&block, "id").unwrap_or_default(),
            title: tag_text(&block, "title").unwrap_or_default(),
            link: extract_link(&block),
            author: child_text(&block, "author", "name")
                .or_else(|| tag_text(&block, "author"))
                .unwrap_or_default(),
            summary: tag_text(&block, "summary").unwrap_or_default(),
            content: tag_text(&block, "content")
                .or_else(|| tag_text(&block, "summary"))
                .unwrap_or_default(),
            published_at: tag_text(&block, "published").or_else(|| tag_text(&block, "updated")),
        })
        .collect()
}

/// Atom link：取 rel=alternate 的 href，否则取第一个 link href
fn extract_link(block: &str) -> String {
    let lower = block.to_lowercase();
    let mut pos = 0;
    while let Some(start) = lower[pos..].find("<link") {
        let abs = pos + start;
        if let Some(gt) = lower[abs..].find('>') {
            let tag = &block[abs..abs + gt + 1];
            let rel = attr(tag, "rel").unwrap_or_else(|| "alternate".to_string());
            if rel == "alternate" {
                if let Some(href) = attr_href(tag) {
                    return href;
                }
            }
            pos = abs + gt + 1;
        } else {
            break;
        }
    }
    // 回退：第一个 link href
    let lower2 = body_lower_first_link(block);
    lower2
}

fn body_lower_first_link(block: &str) -> String {
    let lower = block.to_lowercase();
    if let Some(start) = lower.find("<link") {
        if let Some(gt) = lower[start..].find('>') {
            let tag = &block[start..start + gt + 1];
            if let Some(href) = attr_href(tag) {
                return href;
            }
        }
    }
    String::new()
}

fn attr(tag: &str, name: &str) -> Option<String> {
    let lower = tag.to_lowercase();
    let n = name.to_lowercase();
    for (pat, close) in [(format!("{}=\"", n), '"'), (format!("{}='", n), '\'')] {
        if let Some(start) = lower.find(&pat) {
            let val_start = start + pat.len();
            let rest = &tag[val_start..];
            if let Some(end) = rest.find(close) {
                return Some(rest[..end].to_string());
            }
        }
    }
    None
}

// ============================================================
// 块提取：找出所有 <tag ...> ... </tag> 段落（含嵌套）
// ============================================================

fn extract_blocks(xml: &str, tag: &str) -> Vec<String> {
    let lower = xml.to_lowercase();
    let open = format!("<{}", tag.to_lowercase());
    let close = format!("</{}", tag.to_lowercase());
    let mut blocks = Vec::new();
    let mut pos = 0;

    while let Some(start) = lower[pos..].find(&open) {
        let abs_start = pos + start;
        // 校验标签名边界
        let after = lower[abs_start + open.len()..].chars().next();
        if let Some(c) = after {
            if c.is_alphanumeric() || c == ':' || c == '-' || c == '_' {
                pos = abs_start + open.len();
                continue;
            }
        }
        // 找到该块开头 '>'，然后找匹配的闭合（简单计数）
        let gt = match lower[abs_start..].find('>') {
            Some(i) => abs_start + i,
            None => break,
        };
        // 自闭合跳过
        if lower[abs_start..gt].trim_end().ends_with('/') {
            pos = gt + 1;
            continue;
        }
        // 从 gt 之后寻找闭合标签（处理嵌套：谁先出现处理谁）
        let mut depth = 1;
        let mut scan = gt + 1;
        let mut end = None;
        while scan < lower.len() {
            let next_open = lower[scan..].find(&open);
            let next_close = lower[scan..].find(&close);
            let (rel, is_close) = match (next_open, next_close) {
                (Some(a), Some(b)) => {
                    if a <= b {
                        (a, false)
                    } else {
                        (b, true)
                    }
                }
                (Some(a), None) => (a, false),
                (None, Some(b)) => (b, true),
                (None, None) => break,
            };
            let abs = scan + rel;
            // 注意：闭合标签 `</tag` 比开标签 `<tag` 多一个字符，须用各自的长度
            let tag_len = if is_close { close.len() } else { open.len() };
            let after_c = lower[abs + tag_len..].chars().next();
            let is_real = after_c
                .map_or(true, |c| !(c.is_alphanumeric() || c == ':' || c == '-' || c == '_'));
            if is_real {
                if is_close {
                    depth -= 1;
                    if depth == 0 {
                        end = Some(abs);
                        break;
                    }
                } else {
                    depth += 1;
                }
            }
            scan = abs + tag_len;
        }
        if let Some(end) = end {
            blocks.push(xml[gt + 1..end].to_string());
            pos = end + close.len();
        } else {
            break;
        }
    }
    blocks
}

// ============================================================
// 测试
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rss2() {
        let xml = r#"<?xml version="1.0"?>
        <rss version="2.0"><channel>
          <title>Example</title>
          <item>
            <title>Hello</title>
            <link>https://example.com/1</link>
            <guid>guid-1</guid>
            <pubDate>Mon, 21 Jul 2026 12:00:00 +0800</pubDate>
            <description>Summary here</description>
            <content:encoded><![CDATA[<p>Full content</p>]]></content:encoded>
          </item>
          <item><title>Second</title><link>https://example.com/2</link></item>
        </channel></rss>"#;
        let arts = parse_feed(xml, "");
        assert_eq!(arts.len(), 2);
        assert_eq!(arts[0].title, "Hello");
        assert_eq!(arts[0].guid, "guid-1");
        assert_eq!(arts[0].content, "<p>Full content</p>");
        assert!(arts[0].published_at.is_some());
    }

    #[test]
    fn test_atom() {
        let xml = r#"<?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry>
            <title>Atom Post</title>
            <id>urn:1</id>
            <link rel="alternate" href="https://example.com/a"/>
            <author><name>Alice</name></author>
            <summary>Sum</summary>
            <content type="html">&lt;p&gt;Body&lt;/p&gt;</content>
            <published>2026-07-21T12:00:00Z</published>
          </entry>
        </feed>"#;
        let arts = parse_feed(xml, "");
        assert_eq!(arts.len(), 1);
        assert_eq!(arts[0].title, "Atom Post");
        assert_eq!(arts[0].guid, "urn:1");
        assert_eq!(arts[0].link, "https://example.com/a");
        assert_eq!(arts[0].author, "Alice");
        assert_eq!(arts[0].content, "<p>Body</p>");
        assert_eq!(arts[0].published_at.as_deref(), Some("2026-07-21T12:00:00Z"));
    }
}
