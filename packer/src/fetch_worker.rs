// ============================================================
// 定时抓取任务：扫描启用的 RSS 源，按 rss_sync_state 判断过期，
// 条件请求抓取（ETag / If-Modified-Since），解析后入库。
// 连续失败 >= 5 次的源自动暂停，直到下次成功或重新启用。
// ============================================================

use crate::feed_parser::{self, FeedArticle};
use crate::rss_server::RssDb;
use rusqlite::params;
use std::sync::Arc;
use std::time::Duration;

/// 扫描间隔默认值（分钟），最小值 15
const DEFAULT_SCAN_INTERVAL_MIN: u64 = 15;
/// 源过期时间默认值（分钟）：距上次抓取超过该值才重新抓取
const DEFAULT_FETCH_STALE_MIN: i64 = 30;
/// 连续失败上限，达到后暂停抓取该源
const MAX_FAILURES: i64 = 5;
/// 并发抓取上限
const MAX_CONCURRENT: usize = 4;
/// 响应体上限 10MB
const MAX_BODY_BYTES: usize = 10 * 1024 * 1024;

/// 抓取任务参数（来自 config.toml，可覆盖默认值）
pub struct FetchConfig {
    /// 扫描间隔（分钟），最小 15
    pub scan_interval_min: u64,
    /// 源过期时间（分钟）
    pub fetch_stale_min: i64,
}

impl Default for FetchConfig {
    fn default() -> Self {
        Self {
            scan_interval_min: DEFAULT_SCAN_INTERVAL_MIN,
            fetch_stale_min: DEFAULT_FETCH_STALE_MIN,
        }
    }
}

/// 启动定时抓取任务（后台 tokio 任务，随服务生命周期运行）
/// 通过 RssDb.wake Notify 支持手动触发（POST /api/rss/sync）
pub fn start(db: Arc<RssDb>, cfg: FetchConfig) {
    // 扫描间隔最小 15 分钟
    let scan_min = cfg.scan_interval_min.max(15);
    let scan_interval = Duration::from_secs(scan_min * 60);
    let stale_secs = cfg.fetch_stale_min.max(15) * 60;
    tokio::spawn(async move {
        // 启动时先跑一轮
        tick(&db, stale_secs).await;
        loop {
            tokio::select! {
                _ = tokio::time::sleep(scan_interval) => {}
                _ = db.wake.notified() => {}
            }
            tick(&db, stale_secs).await;
        }
    });
}

struct PendingSource {
    id: i64,
    url: String,
    feed_type: String,
    etag: String,
    last_modified: String,
}

async fn tick(db: &Arc<RssDb>, fetch_stale_secs: i64) {
    let pending = collect_pending(db, fetch_stale_secs);
    if pending.is_empty() {
        return;
    }

    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("ZebraRSS/1.0 (+https://zebra.dart.xin)")
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[rss-fetch] Failed to build client: {}", e);
            return;
        }
    };

    let semaphore = Arc::new(tokio::sync::Semaphore::new(MAX_CONCURRENT));
    let mut handles = Vec::new();
    for source in pending {
        let client = client.clone();
        let db = db.clone();
        let sem = semaphore.clone();
        handles.push(tokio::spawn(async move {
            let _permit = sem.acquire().await.unwrap();
            fetch_one(&client, &db, source).await;
        }));
    }
    for h in handles {
        let _ = h.await;
    }
}

/// 收集待抓取源：enabled=1 且未达失败上限，且超过过期时间
fn collect_pending(db: &Arc<RssDb>, fetch_stale_secs: i64) -> Vec<PendingSource> {
    let conn = match db.db.lock() {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let sql = r#"
        SELECT s.id, s.url, s.feed_type,
               COALESCE(st.etag, ''),
               COALESCE(st.last_modified, '')
        FROM rss_sources s
        LEFT JOIN rss_sync_state st ON st.source_id = s.id
        WHERE s.enabled = 1
          AND s.fetch_enabled = 1
          AND (st.consecutive_failures IS NULL OR st.consecutive_failures < ?1)
          AND (st.last_fetch_at IS NULL OR st.last_fetch_at = ''
               OR strftime('%s','now') - strftime('%s', st.last_fetch_at) >= ?2)
        ORDER BY s.id
    "#;

    let mut stmt = match conn.prepare(sql) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[rss-fetch] prepare failed: {}", e);
            return Vec::new();
        }
    };
    let rows = match stmt.query_map(params![MAX_FAILURES, fetch_stale_secs], |r| {
        Ok(PendingSource {
            id: r.get(0)?,
            url: r.get(1)?,
            feed_type: r.get(2)?,
            etag: r.get(3)?,
            last_modified: r.get(4)?,
        })
    }) {
        Ok(rows) => rows,
        Err(e) => {
            eprintln!("[rss-fetch] query failed: {}", e);
            return Vec::new();
        }
    };

    rows.filter_map(|r| r.ok()).collect()
}

async fn fetch_one(client: &reqwest::Client, db: &Arc<RssDb>, source: PendingSource) {
    let mut req = client.get(&source.url);
    if !source.etag.is_empty() {
        req = req.header(reqwest::header::IF_NONE_MATCH, &source.etag);
    }
    if !source.last_modified.is_empty() {
        req = req.header(reqwest::header::IF_MODIFIED_SINCE, &source.last_modified);
    }

    let resp = match req.send().await {
        Ok(r) => r,
        Err(e) => {
            record_failure(db, source.id, &format!("fetch error: {}", e));
            return;
        }
    };

    // 304 Not Modified：内容未变化
    if resp.status() == reqwest::StatusCode::NOT_MODIFIED {
        update_fetched(db, source.id);
        return;
    }

    if !resp.status().is_success() {
        record_failure(db, source.id, &format!("HTTP {}", resp.status().as_u16()));
        return;
    }

    let new_etag = resp
        .headers()
        .get(reqwest::header::ETAG)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();
    let new_modified = resp
        .headers()
        .get(reqwest::header::LAST_MODIFIED)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    let bytes = match resp.bytes().await {
        Ok(b) => b,
        Err(e) => {
            record_failure(db, source.id, &format!("body error: {}", e));
            return;
        }
    };
    if bytes.len() > MAX_BODY_BYTES {
        record_failure(db, source.id, "response too large");
        return;
    }
    let text = String::from_utf8_lossy(&bytes).to_string();

    let articles = feed_parser::parse_feed(&text, &source.feed_type);
    let inserted = insert_articles(db, source.id, &articles);
    update_success(db, source.id, &new_etag, &new_modified, inserted);
}

/// 批量插入文章（INSERT OR IGNORE 按 (source_id, guid) 去重），返回新增数
fn insert_articles(db: &Arc<RssDb>, source_id: i64, articles: &[FeedArticle]) -> usize {
    if articles.is_empty() {
        return 0;
    }
    let conn = match db.db.lock() {
        Ok(c) => c,
        Err(_) => return 0,
    };
    let _ = conn.execute_batch("BEGIN");
    let mut inserted = 0;
    {
        let mut stmt = match conn.prepare(
            "INSERT OR IGNORE INTO rss_articles
                (source_id, guid, title, link, author, summary, content, published_at, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, datetime('now'), datetime('now'))",
        ) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[rss-fetch] insert prepare failed: {}", e);
                let _ = conn.execute_batch("ROLLBACK");
                return 0;
            }
        };
        for a in articles {
            let n = stmt
                .execute(params![
                    source_id,
                    a.guid,
                    a.title,
                    a.link,
                    a.author,
                    a.summary,
                    a.content,
                    a.published_at,
                ])
                .unwrap_or(0);
            inserted += n;
        }
    }
    let _ = conn.execute_batch("COMMIT");
    inserted
}

/// 抓取成功：更新同步状态
fn update_success(db: &Arc<RssDb>, source_id: i64, etag: &str, last_modified: &str, inserted: usize) {
    let conn = match db.db.lock() {
        Ok(c) => c,
        Err(_) => return,
    };
    let _ = conn.execute(
        "INSERT INTO rss_sync_state (source_id, last_fetch_at, etag, last_modified, consecutive_failures, last_error)
         VALUES (?1, datetime('now'), ?2, ?3, 0, '')
         ON CONFLICT(source_id) DO UPDATE SET
            last_fetch_at = datetime('now'),
            etag = ?2,
            last_modified = ?3,
            consecutive_failures = 0,
            last_error = ''",
        params![source_id, etag, last_modified],
    );
    if inserted > 0 {
        eprintln!("[rss-fetch] source {}: +{} articles", source_id, inserted);
    }
}

/// 304：内容未变，只更新时间戳与清零失败计数
fn update_fetched(db: &Arc<RssDb>, source_id: i64) {
    let conn = match db.db.lock() {
        Ok(c) => c,
        Err(_) => return,
    };
    let _ = conn.execute(
        "INSERT INTO rss_sync_state (source_id, last_fetch_at, consecutive_failures, last_error)
         VALUES (?1, datetime('now'), 0, '')
         ON CONFLICT(source_id) DO UPDATE SET
            last_fetch_at = datetime('now'),
            consecutive_failures = 0,
            last_error = ''",
        params![source_id],
    );
}

/// 抓取失败：记录错误并累计失败次数
fn record_failure(db: &Arc<RssDb>, source_id: i64, message: &str) {
    let conn = match db.db.lock() {
        Ok(c) => c,
        Err(_) => return,
    };
    let _ = conn.execute(
        "INSERT INTO rss_sync_state (source_id, last_error, consecutive_failures)
         VALUES (?1, ?2, 1)
         ON CONFLICT(source_id) DO UPDATE SET
            last_error = ?2,
            consecutive_failures = consecutive_failures + 1",
        params![source_id, message],
    );
    eprintln!("[rss-fetch] source {} failed: {}", source_id, message);
}
