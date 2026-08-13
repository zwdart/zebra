use axum::{
    Json, Router,
    extract::{Multipart, State},
    http::StatusCode,
    response::{Html, IntoResponse},
    routing::{get, post},
};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::path::PathBuf;

// ============================================================
// RSS 数据源独立数据库
// ============================================================

pub struct RssDb {
    pub db: Mutex<Connection>,
    /// 手动触发抓取唤醒（POST /api/rss/sync 时 notify）
    pub wake: tokio::sync::Notify,
    /// 扫描间隔（分钟，来自 config.toml rss_scan_interval_min，默认 15，最小 15）
    pub scan_interval_min: u64,
    /// 源过期重抓时间（分钟，来自 config.toml rss_fetch_stale_min，默认 30）
    pub fetch_stale_min: i64,
}

impl RssDb {
    pub fn open(data_dir: &str) -> Self {
        let db_dir = PathBuf::from(data_dir);
        std::fs::create_dir_all(&db_dir).ok();
        let db_path = db_dir.join("zebra_rss.db");
        let conn = Connection::open(&db_path).expect("Failed to open RSS database");

        conn.execute_batch("PRAGMA journal_mode=WAL;").ok();

        conn.execute_batch("
            CREATE TABLE IF NOT EXISTS rss_sources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL,
                site_url TEXT DEFAULT '',
                feed_type TEXT NOT NULL DEFAULT 'rss2',
                category TEXT DEFAULT '',
                enabled INTEGER NOT NULL DEFAULT 1,
                fetch_enabled INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_rss_sources_url ON rss_sources(url);
            CREATE INDEX IF NOT EXISTS idx_rss_sources_enabled ON rss_sources(enabled);
            CREATE INDEX IF NOT EXISTS idx_rss_sources_fetch ON rss_sources(fetch_enabled);
            CREATE INDEX IF NOT EXISTS idx_rss_sources_category ON rss_sources(category);

            CREATE TABLE IF NOT EXISTS rss_folders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                description TEXT DEFAULT '',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS rss_folder_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                folder_id INTEGER NOT NULL,
                source_id INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (folder_id) REFERENCES rss_folders(id) ON DELETE CASCADE,
                FOREIGN KEY (source_id) REFERENCES rss_sources(id) ON DELETE CASCADE,
                UNIQUE(folder_id, source_id)
            );
            CREATE INDEX IF NOT EXISTS idx_folder_items_folder ON rss_folder_items(folder_id);
            CREATE INDEX IF NOT EXISTS idx_folder_items_source ON rss_folder_items(source_id);

            -- 文章表：服务端统一存储抓取结果
            CREATE TABLE IF NOT EXISTS rss_articles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_id INTEGER NOT NULL REFERENCES rss_sources(id) ON DELETE CASCADE,
                guid TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL DEFAULT '',
                link TEXT NOT NULL DEFAULT '',
                author TEXT DEFAULT '',
                summary TEXT DEFAULT '',
                content TEXT DEFAULT '',
                published_at TEXT DEFAULT NULL,
                is_read INTEGER NOT NULL DEFAULT 0,
                is_starred INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(source_id, guid)
            );
            CREATE INDEX IF NOT EXISTS idx_rss_articles_source ON rss_articles(source_id);
            CREATE INDEX IF NOT EXISTS idx_rss_articles_published ON rss_articles(published_at DESC);
            CREATE INDEX IF NOT EXISTS idx_rss_articles_read ON rss_articles(is_read);
            CREATE INDEX IF NOT EXISTS idx_rss_articles_starred ON rss_articles(is_starred);

            -- 抓取状态表：每源最近抓取结果、ETag、失败次数
            CREATE TABLE IF NOT EXISTS rss_sync_state (
                source_id INTEGER PRIMARY KEY REFERENCES rss_sources(id) ON DELETE CASCADE,
                last_fetch_at TEXT DEFAULT NULL,
                etag TEXT DEFAULT '',
                last_modified TEXT DEFAULT '',
                consecutive_failures INTEGER NOT NULL DEFAULT 0,
                last_error TEXT DEFAULT ''
            );

            -- 全文搜索（服务端检索）
            CREATE VIRTUAL TABLE IF NOT EXISTS rss_articles_fts USING fts5(
                title, summary, content,
                content='rss_articles', content_rowid='id',
                tokenize='unicode61'
            );
            CREATE TRIGGER IF NOT EXISTS rss_articles_fts_ai AFTER INSERT ON rss_articles BEGIN
                INSERT INTO rss_articles_fts(rowid, title, summary, content)
                VALUES (new.id, new.title, new.summary, new.content);
            END;
            CREATE TRIGGER IF NOT EXISTS rss_articles_fts_ad AFTER DELETE ON rss_articles BEGIN
                INSERT INTO rss_articles_fts(rss_articles_fts, rowid, title, summary, content)
                VALUES ('delete', old.id, old.title, old.summary, old.content);
            END;
            CREATE TRIGGER IF NOT EXISTS rss_articles_fts_au AFTER UPDATE ON rss_articles BEGIN
                INSERT INTO rss_articles_fts(rss_articles_fts, rowid, title, summary, content)
                VALUES ('delete', old.id, old.title, old.summary, old.content);
                INSERT INTO rss_articles_fts(rowid, title, summary, content)
                VALUES (new.id, new.title, new.summary, new.content);
            END;
        ").expect("Failed to create RSS tables");

        // 老库迁移：rss_sources 补 fetch_enabled 列（默认开启抓取）
        {
            let mut cols: Vec<String> = Vec::new();
            if let Ok(mut stmt) = conn.prepare("PRAGMA table_info(rss_sources)") {
                if let Ok(rows) = stmt.query_map([], |r| r.get::<_, String>(1)) {
                    for row in rows.flatten() {
                        cols.push(row);
                    }
                }
            }
            if !cols.iter().any(|c| c == "fetch_enabled") {
                conn.execute_batch(
                    "ALTER TABLE rss_sources ADD COLUMN fetch_enabled INTEGER NOT NULL DEFAULT 1;
                     CREATE INDEX IF NOT EXISTS idx_rss_sources_fetch ON rss_sources(fetch_enabled);",
                )
                .ok();
            }
        }

        // 老库已有文章但 FTS 为空时，重建一次索引
        {
            let fts_cnt: i64 = conn
                .query_row("SELECT COUNT(*) FROM rss_articles_fts", [], |r| r.get(0))
                .unwrap_or(0);
            let art_cnt: i64 = conn
                .query_row("SELECT COUNT(*) FROM rss_articles", [], |r| r.get(0))
                .unwrap_or(0);
            if fts_cnt == 0 && art_cnt > 0 {
                conn.execute_batch("INSERT INTO rss_articles_fts(rss_articles_fts) VALUES('rebuild');")
                    .ok();
            }
        }

        Self {
            db: Mutex::new(conn),
            wake: tokio::sync::Notify::new(),
            scan_interval_min: 15,
            fetch_stale_min: 30,
        }
    }

    /// 设置抓取间隔（启动时由 config.toml 覆盖，分钟单位）
    pub fn set_fetch_interval(&mut self, scan_interval_min: u64, fetch_stale_min: i64) {
        self.scan_interval_min = scan_interval_min.max(15);
        self.fetch_stale_min = fetch_stale_min;
    }
}

// ============================================================
// 数据模型
// ============================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct RssSource {
    pub id: Option<i64>,
    pub title: String,
    pub url: String,
    #[serde(default)]
    pub site_url: String,
    #[serde(default = "default_feed_type")]
    pub feed_type: String,
    #[serde(default)]
    pub category: String,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default = "default_enabled")]
    pub fetch_enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
}

fn default_feed_type() -> String { "rss2".to_string() }
fn default_enabled() -> bool { true }

#[derive(Debug, Deserialize)]
pub struct RssSourceQuery {
    pub page: Option<i64>,
    pub size: Option<i64>,
    pub category: Option<String>,
    pub search: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BatchDeleteRequest {
    pub ids: Vec<i64>,
}

#[derive(Debug, Serialize)]
pub struct PaginatedRssSources {
    pub data: Vec<RssSource>,
    pub total: i64,
    pub page: i64,
    pub size: i64,
}

// ============================================================
// 收藏夹 (Folders)
// ============================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct RssFolder {
    pub id: Option<i64>,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_count: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct RssFolderQuery {
    pub page: Option<i64>,
    pub size: Option<i64>,
    pub search: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AddSourceToFolderRequest {
    pub source_id: i64,
}

#[derive(Debug, Deserialize)]
pub struct BatchAddSourcesToFolderRequest {
    pub source_ids: Vec<i64>,
}

#[derive(Debug, Serialize)]
pub struct PaginatedRssFolders {
    pub data: Vec<RssFolder>,
    pub total: i64,
    pub page: i64,
    pub size: i64,
}

/// GET /api/rss/folders — 获取所有收藏夹（公开）
pub async fn list_rss_folders(
    State(state): State<Arc<RssDb>>,
    axum::extract::Query(query): axum::extract::Query<RssFolderQuery>,
) -> Json<PaginatedRssFolders> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(50).min(100);
    let offset = (page - 1) * size;
    let db = state.db.lock().unwrap();

    let mut where_clause = String::new();
    let mut param_values: Vec<String> = Vec::new();

    if let Some(ref search) = query.search {
        if !search.is_empty() {
            where_clause = " WHERE name LIKE ?1".to_string();
            param_values.push(format!("%{}%", search));
        }
    }

    let count_sql = format!("SELECT COUNT(*) FROM rss_folders{}", where_clause);
    let total: i64 = if let Ok(mut stmt) = db.prepare(&count_sql) {
        let refs: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|s| s as &dyn rusqlite::types::ToSql).collect();
        stmt.query_row(refs.as_slice(), |r| r.get(0)).unwrap_or(0)
    } else {
        0
    };

    let sql = format!(
        "SELECT id, name, description, created_at, updated_at FROM rss_folders{} ORDER BY created_at DESC LIMIT {} OFFSET {}",
        where_clause, size, offset
    );

    let folders = if let Ok(mut stmt) = db.prepare(&sql) {
        let refs: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|s| s as &dyn rusqlite::types::ToSql).collect();
        stmt.query_map(refs.as_slice(), |row| {
            let folder_id: i64 = row.get(0)?;
            let name: String = row.get(1)?;
            let description: String = row.get(2)?;
            let created_at: Option<String> = row.get(3)?;
            let updated_at: Option<String> = row.get(4)?;

            // Count sources in this folder
            let count: i64 = db.prepare("SELECT COUNT(*) FROM rss_folder_items WHERE folder_id = ?")
                .and_then(|mut s| s.query_row([folder_id], |r| r.get(0)))
                .unwrap_or(0);

            Ok(RssFolder {
                id: Some(folder_id),
                name,
                description,
                created_at,
                updated_at,
                source_count: Some(count),
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
    } else {
        vec![]
    };

    Json(PaginatedRssFolders { data: folders, total, page, size })
}

/// POST /api/admin/rss/folders — 创建收藏夹
pub async fn admin_create_folder(
    State(state): State<Arc<RssDb>>,
    Json(body): Json<RssFolder>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    db.execute(
        "INSERT INTO rss_folders (name, description, created_at, updated_at) VALUES (?1, ?2, datetime('now'), datetime('now'))",
        params![body.name, body.description],
    ).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let id = db.last_insert_rowid();
    Ok(Json(serde_json::json!({ "success": true, "data": { "id": id, "name": body.name, "description": body.description } })))
}

/// PUT /api/admin/rss/folders/{id} — 更新收藏夹
pub async fn admin_update_folder(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<RssFolder>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    db.execute(
        "UPDATE rss_folders SET name = ?1, description = ?2, updated_at = datetime('now') WHERE id = ?3",
        params![body.name, body.description, id],
    ).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "success": true })))
}

/// DELETE /api/admin/rss/folders/{id} — 删除收藏夹
pub async fn admin_delete_folder(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    db.execute("DELETE FROM rss_folder_items WHERE folder_id = ?", params![id])
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    db.execute("DELETE FROM rss_folders WHERE id = ?", params![id])
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "success": true })))
}

/// GET /api/admin/rss/folders/{id}/sources — 获取收藏夹内的订阅源
pub async fn admin_folder_sources(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    axum::extract::Query(query): axum::extract::Query<RssSourceQuery>,
) -> Json<PaginatedRssSources> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(50).min(100);
    let offset = (page - 1) * size;
    let db = state.db.lock().unwrap();

    let total: i64 = db.prepare("SELECT COUNT(*) FROM rss_folder_items WHERE folder_id = ?")
        .and_then(|mut stmt| stmt.query_row([id], |r| r.get(0)))
        .unwrap_or(0);

    let sql = format!(
        "SELECT s.id, s.title, s.url, s.site_url, s.feed_type, s.category, s.enabled, s.fetch_enabled, s.created_at, s.updated_at
         FROM rss_sources s INNER JOIN rss_folder_items f ON s.id = f.source_id
         WHERE f.folder_id = {} ORDER BY f.created_at DESC LIMIT {} OFFSET {}",
        id, size, offset
    );

    let sources = if let Ok(mut stmt) = db.prepare(&sql) {
        stmt.query_map([], |row| {
            Ok(RssSource {
                id: row.get(0)?,
                title: row.get(1)?,
                url: row.get(2)?,
                site_url: row.get(3)?,
                feed_type: row.get(4)?,
                category: row.get(5)?,
                enabled: row.get::<_, i64>(6)? == 1,
                fetch_enabled: row.get::<_, i64>(7)? == 1,
                created_at: row.get(8)?,
                updated_at: row.get(9)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
    } else {
        vec![]
    };

    Json(PaginatedRssSources { data: sources, total, page, size })
}

/// POST /api/admin/rss/folders/{id}/sources — 向收藏夹添加订阅源
pub async fn admin_add_source_to_folder(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<AddSourceToFolderRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    let result = db.execute(
        "INSERT OR IGNORE INTO rss_folder_items (folder_id, source_id, created_at) VALUES (?1, ?2, datetime('now'))",
        params![id, body.source_id],
    ).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "success": true, "added": result > 0 })))
}

/// POST /api/admin/rss/folders/{id}/sources/batch — 批量添加订阅源到收藏夹
pub async fn admin_batch_add_sources_to_folder(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<BatchAddSourcesToFolderRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    let mut added = 0;
    for source_id in &body.source_ids {
        let result = db.execute(
            "INSERT OR IGNORE INTO rss_folder_items (folder_id, source_id, created_at) VALUES (?1, ?2, datetime('now'))",
            params![id, source_id],
        ).unwrap_or(0);
        if result > 0 { added += 1; }
    }
    Ok(Json(serde_json::json!({ "success": true, "added": added })))
}

/// DELETE /api/admin/rss/folders/{id}/sources/{source_id} — 从收藏夹移除订阅源
pub async fn admin_remove_source_from_folder(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path((id, source_id)): axum::extract::Path<(i64, i64)>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    db.execute(
        "DELETE FROM rss_folder_items WHERE folder_id = ? AND source_id = ?",
        params![id, source_id],
    ).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "success": true })))
}

/// POST /api/admin/rss/folders/{id}/sources/batch-delete — 批量从收藏夹移除订阅源
pub async fn admin_batch_remove_sources_from_folder(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(folder_id): axum::extract::Path<i64>,
    Json(payload): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let source_ids = payload.get("source_ids")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_i64()).collect::<Vec<i64>>())
        .unwrap_or_default();

    if source_ids.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let db = state.db.lock().unwrap();
    let mut removed = 0;

    for source_id in &source_ids {
        let result = db.execute(
            "DELETE FROM rss_folder_items WHERE folder_id = ? AND source_id = ?",
            params![folder_id, source_id],
        );
        if result.is_ok() {
            removed += 1;
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "removed": removed })))
}

/// GET /api/rss/folders/{id}/sources — 公开获取收藏夹内的订阅源（客户端用）
pub async fn list_folder_sources(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    axum::extract::Query(query): axum::extract::Query<RssSourceQuery>,
) -> Json<PaginatedRssSources> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(50).min(100);
    let offset = (page - 1) * size;
    let db = state.db.lock().unwrap();

    let total: i64 = db.prepare("SELECT COUNT(*) FROM rss_folder_items f INNER JOIN rss_sources s ON f.source_id = s.id WHERE f.folder_id = ? AND s.enabled = 1")
        .and_then(|mut stmt| stmt.query_row([id], |r| r.get(0)))
        .unwrap_or(0);

    let sql = format!(
        "SELECT s.id, s.title, s.url, s.site_url, s.feed_type, s.category, s.enabled, s.fetch_enabled, s.created_at, s.updated_at
         FROM rss_sources s INNER JOIN rss_folder_items f ON s.id = f.source_id
         WHERE f.folder_id = {} AND s.enabled = 1 ORDER BY f.created_at DESC LIMIT {} OFFSET {}",
        id, size, offset
    );

    let sources = if let Ok(mut stmt) = db.prepare(&sql) {
        stmt.query_map([], |row| {
            Ok(RssSource {
                id: row.get(0)?,
                title: row.get(1)?,
                url: row.get(2)?,
                site_url: row.get(3)?,
                feed_type: row.get(4)?,
                category: row.get(5)?,
                enabled: row.get::<_, i64>(6)? == 1,
                fetch_enabled: row.get::<_, i64>(7)? == 1,
                created_at: row.get(8)?,
                updated_at: row.get(9)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
    } else {
        vec![]
    };

    Json(PaginatedRssSources { data: sources, total, page, size })
}

// ============================================================
// 公开 API
// ============================================================

/// GET /api/rss/sources — 获取启用的 RSS 源列表
pub async fn list_rss_sources(
    State(state): State<Arc<RssDb>>,
    axum::extract::Query(query): axum::extract::Query<RssSourceQuery>,
) -> Json<PaginatedRssSources> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(20).min(100);
    let offset = (page - 1) * size;
    let db = state.db.lock().unwrap();

    let total: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_sources WHERE enabled = 1", [], |r| r.get(0))
        .unwrap_or(0);

    let mut sql = "SELECT id, title, url, site_url, feed_type, category, enabled, fetch_enabled, created_at, updated_at FROM rss_sources WHERE enabled = 1".to_string();

    let mut param_values: Vec<String> = Vec::new();

    if let Some(ref category) = query.category {
        if !category.is_empty() && category != "all" {
            sql.push_str(" AND category = ?1");
            param_values.push(category.clone());
        }
    }

    if let Some(ref search) = query.search {
        if !search.is_empty() {
            let idx = param_values.len() + 1;
            sql.push_str(&format!(" AND (title LIKE ?{} OR url LIKE ?{} OR category LIKE ?{})", idx, idx, idx));
            param_values.push(format!("%{}%", search));
        }
    }

    sql.push_str(" ORDER BY created_at DESC LIMIT ? OFFSET ?");
    let limit = size.to_string();
    let off = offset.to_string();
    param_values.push(limit);
    param_values.push(off);

    let refs: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|s| s as &dyn rusqlite::types::ToSql).collect();

    let sources = if let Ok(mut stmt) = db.prepare(&sql) {
        stmt.query_map(refs.as_slice(), |row| {
            Ok(RssSource {
                id: row.get(0)?,
                title: row.get(1)?,
                url: row.get(2)?,
                site_url: row.get(3)?,
                feed_type: row.get(4)?,
                category: row.get(5)?,
                enabled: row.get::<_, i64>(6)? == 1,
                fetch_enabled: row.get::<_, i64>(7)? == 1,
                created_at: row.get(8)?,
                updated_at: row.get(9)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
    } else {
        vec![]
    };

    Json(PaginatedRssSources { data: sources, total, page, size })
}

// ============================================================
// 管理 API
// ============================================================

/// GET /api/admin/rss/sources — 管理员获取所有 RSS 源
pub async fn admin_list_rss_sources(
    State(state): State<Arc<RssDb>>,
    axum::extract::Query(query): axum::extract::Query<RssSourceQuery>,
) -> Json<PaginatedRssSources> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(20).min(100);
    let offset = (page - 1) * size;
    let db = state.db.lock().unwrap();

    let total: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_sources", [], |r| r.get(0))
        .unwrap_or(0);

    let mut sql = "SELECT id, title, url, site_url, feed_type, category, enabled, fetch_enabled, created_at, updated_at FROM rss_sources".to_string();
    let mut param_values: Vec<String> = Vec::new();

    if let Some(ref category) = query.category {
        if !category.is_empty() && category != "all" {
            sql.push_str(" WHERE category = ?1");
            param_values.push(category.clone());
        }
    }

    if let Some(ref search) = query.search {
        if !search.is_empty() {
            if param_values.is_empty() {
                sql.push_str(" WHERE ");
            } else {
                sql.push_str(" AND ");
            }
            let idx = param_values.len() + 1;
            sql.push_str(&format!("(title LIKE ?{} OR url LIKE ?{} OR category LIKE ?{})", idx, idx, idx));
            param_values.push(format!("%{}%", search));
        }
    }

    sql.push_str(" ORDER BY created_at DESC LIMIT ? OFFSET ?");
    param_values.push(size.to_string());
    param_values.push(offset.to_string());

    let refs: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|s| s as &dyn rusqlite::types::ToSql).collect();

    let sources = if let Ok(mut stmt) = db.prepare(&sql) {
        stmt.query_map(refs.as_slice(), |row| {
            Ok(RssSource {
                id: row.get(0)?,
                title: row.get(1)?,
                url: row.get(2)?,
                site_url: row.get(3)?,
                feed_type: row.get(4)?,
                category: row.get(5)?,
                enabled: row.get::<_, i64>(6)? == 1,
                fetch_enabled: row.get::<_, i64>(7)? == 1,
                created_at: row.get(8)?,
                updated_at: row.get(9)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
    } else {
        vec![]
    };

    Json(PaginatedRssSources { data: sources, total, page, size })
}

/// POST /api/admin/rss/sources — 创建 RSS 源
pub async fn admin_create_rss_source(
    State(state): State<Arc<RssDb>>,
    Json(body): Json<RssSource>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    let enabled = if body.enabled { 1 } else { 0 };
    let fetch_enabled = if body.fetch_enabled { 1 } else { 0 };

    db.execute(
        "INSERT INTO rss_sources (title, url, site_url, feed_type, category, enabled, fetch_enabled, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now'), datetime('now'))",
        params![body.title, body.url, body.site_url, body.feed_type, body.category, enabled, fetch_enabled],
    ).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let id = db.last_insert_rowid();

    Ok(Json(serde_json::json!({
        "success": true,
        "data": {
            "id": id,
            "title": body.title,
            "url": body.url,
            "site_url": body.site_url,
            "feed_type": body.feed_type,
            "category": body.category,
            "enabled": body.enabled,
            "fetch_enabled": body.fetch_enabled,
        }
    })))
}

/// PUT /api/admin/rss/sources/{id} — 更新 RSS 源
pub async fn admin_update_rss_source(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<RssSource>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    let enabled = if body.enabled { 1 } else { 0 };
    let fetch_enabled = if body.fetch_enabled { 1 } else { 0 };

    db.execute(
        "UPDATE rss_sources SET title = ?1, url = ?2, site_url = ?3, feed_type = ?4,
         category = ?5, enabled = ?6, fetch_enabled = ?7, updated_at = datetime('now') WHERE id = ?8",
        params![body.title, body.url, body.site_url, body.feed_type, body.category, enabled, fetch_enabled, id],
    ).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(serde_json::json!({ "success": true })))
}

/// DELETE /api/admin/rss/sources/{id} — 删除 RSS 源
pub async fn admin_delete_rss_source(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    db.execute("DELETE FROM rss_sources WHERE id = ?", params![id])
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "success": true })))
}

/// POST /api/admin/rss/sources/batch-delete — 批量删除
pub async fn admin_batch_delete_rss_sources(
    State(state): State<Arc<RssDb>>,
    Json(body): Json<BatchDeleteRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    if body.ids.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let db = state.db.lock().unwrap();
    let placeholders: Vec<String> = body.ids.iter().map(|_| "?".to_string()).collect();
    let sql = format!("DELETE FROM rss_sources WHERE id IN ({})", placeholders.join(","));
    let refs: Vec<&dyn rusqlite::types::ToSql> = body.ids.iter().map(|id| id as &dyn rusqlite::types::ToSql).collect();
    db.execute(&sql, refs.as_slice()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "success": true, "deleted": body.ids.len() })))
}

/// GET /api/admin/rss/sources/export — 导出 CSV
pub async fn admin_export_rss_sources_csv(
    State(state): State<Arc<RssDb>>,
) -> impl IntoResponse {
    let db = state.db.lock().unwrap();
    let mut csv = String::from("title,url,site_url,feed_type,category,enabled,fetch_enabled\n");

    if let Ok(mut stmt) = db.prepare("SELECT title, url, site_url, feed_type, category, enabled, fetch_enabled FROM rss_sources ORDER BY created_at DESC") {
        if let Ok(rows) = stmt.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, i64>(5)?,
                row.get::<_, i64>(6)?,
            ))
        }) {
            for row in rows.flatten() {
                let enabled = if row.5 == 1 { "true" } else { "false" };
                let fetch_enabled = if row.6 == 1 { "true" } else { "false" };
                csv.push_str(&format!("\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\"\n",
                    row.0.replace('"', "\"\""), row.1.replace('"', "\"\""),
                    row.2.replace('"', "\"\""), row.3.replace('"', "\"\""),
                    row.4.replace('"', "\"\""), enabled, fetch_enabled));
            }
        }
    }

    (
        [(axum::http::header::CONTENT_TYPE, "text/csv; charset=utf-8"),
         (axum::http::header::CONTENT_DISPOSITION, "attachment; filename=\"rss_sources.csv\"")],
        csv,
    )
}

/// POST /api/admin/rss/sources/import — 导入 CSV
pub async fn admin_import_rss_sources_csv(
    State(state): State<Arc<RssDb>>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let mut file_data = Vec::new();

    while let Some(field) = multipart.next_field().await.map_err(|_| StatusCode::BAD_REQUEST)? {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" || name.is_empty() {
            let data = field.bytes().await.map_err(|_| StatusCode::BAD_REQUEST)?;
            file_data = data.to_vec();
            break;
        }
    }

    if file_data.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let content = String::from_utf8(file_data).map_err(|_| StatusCode::BAD_REQUEST)?;
    let db = state.db.lock().unwrap();
    let mut imported = 0;

    for (i, line) in content.lines().enumerate() {
        if i == 0 { continue; } // skip header
        let fields = parse_csv_line(line);
        if fields.len() < 2 { continue; }
        let title = fields[0].clone();
        let url = fields[1].clone();
        let site_url = fields.get(2).cloned().unwrap_or_default();
        let feed_type = fields.get(3).cloned().unwrap_or_else(|| "rss2".to_string());
        let category = fields.get(4).cloned().unwrap_or_default();
        let enabled = fields.get(5).cloned().unwrap_or_else(|| "true".to_string()) != "false";
        let fetch_enabled = fields.get(6).cloned().unwrap_or_else(|| "true".to_string()) != "false";

        let enabled_val = if enabled { 1 } else { 0 };
        let fetch_enabled_val = if fetch_enabled { 1 } else { 0 };
        let result = db.execute(
            "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, category, enabled, fetch_enabled, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now'), datetime('now'))",
            params![title, url, site_url, feed_type, category, enabled_val, fetch_enabled_val],
        );
        if result.is_ok() {
            imported += 1;
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "imported": imported })))
}

/// GET /api/admin/rss/sources/export/opml — 导出 OPML
pub async fn admin_export_rss_sources_opml(
    State(state): State<Arc<RssDb>>,
) -> impl IntoResponse {
    let db = state.db.lock().unwrap();
    let mut opml = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">\n<head><title>Zebra RSS Sources</title></head>\n<body>\n");

    if let Ok(mut stmt) = db.prepare("SELECT title, url, site_url FROM rss_sources ORDER BY created_at DESC") {
        if let Ok(rows) = stmt.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?))
        }) {
            for row in rows.flatten() {
                opml.push_str(&format!("  <outline text=\"{}\" title=\"{}\" type=\"rss\" xmlUrl=\"{}\" htmlUrl=\"{}\"/>\n",
                    xml_escape(&row.0), xml_escape(&row.0), xml_escape(&row.1), xml_escape(&row.2)));
            }
        }
    }

    opml.push_str("</body>\n</opml>");

    (
        [(axum::http::header::CONTENT_TYPE, "application/xml; charset=utf-8"),
         (axum::http::header::CONTENT_DISPOSITION, "attachment; filename=\"rss_sources.opml\"")],
        opml,
    )
}

/// POST /api/admin/rss/sources/import/opml — 导入 OPML
pub async fn admin_import_rss_sources_opml(
    State(state): State<Arc<RssDb>>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let mut file_data = Vec::new();

    while let Some(field) = multipart.next_field().await.map_err(|_| StatusCode::BAD_REQUEST)? {
        let data = field.bytes().await.map_err(|_| StatusCode::BAD_REQUEST)?;
        file_data = data.to_vec();
        break;
    }

    if file_data.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let content = String::from_utf8(file_data).map_err(|_| StatusCode::BAD_REQUEST)?;
    let db = state.db.lock().unwrap();
    let mut imported = 0;

    // Simple OPML parsing - find all <outline> with xmlUrl
    let mut pos = 0;
    while let Some(start) = content[pos..].find("<outline") {
        let abs_start = pos + start;
        if let Some(end) = content[abs_start..].find('>') {
            let tag = &content[abs_start..abs_start + end + 1];
            pos = abs_start + end + 1;

            if let Some(xml_url) = extract_attr(tag, "xmlUrl").or_else(|| extract_attr(tag, "xmlurl")) {
                let title = extract_attr(tag, "title")
                    .or_else(|| extract_attr(tag, "text"))
                    .unwrap_or_else(|| xml_url.clone());
                let html_url = extract_attr(tag, "htmlUrl")
                    .or_else(|| extract_attr(tag, "htmlurl"))
                    .unwrap_or_default();

                let result = db.execute(
                    "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, enabled, created_at, updated_at)
                     VALUES (?1, ?2, ?3, 'rss2', 1, datetime('now'), datetime('now'))",
                    params![title, xml_url, html_url],
                );
                if result.is_ok() {
                    imported += 1;
                }
            }
        } else {
            break;
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "imported": imported })))
}

/// GET /api/admin/rss — 管理后台页面
pub async fn admin_rss_page(
    State(_state): State<Arc<RssDb>>,
) -> Html<String> {
    // Try loading from static dir first, fallback to embedded
    let static_dir = std::env::var("ZEBRA_STATIC_DIR").unwrap_or_else(|_| "static".to_string());
    let path = std::path::Path::new(&static_dir).join("rss_admin.html");
    let html = if path.exists() {
        std::fs::read_to_string(&path).unwrap_or_else(|_| include_str!("../static/rss_admin.html").to_string())
    } else {
        include_str!("../static/rss_admin.html").to_string()
    };
    Html(html)
}

// ============================================================
// 工具函数
// ============================================================

fn parse_csv_line(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if in_quotes {
            if c == '"' {
                if i + 1 < chars.len() && chars[i + 1] == '"' {
                    current.push('"');
                    i += 2;
                    continue;
                } else {
                    in_quotes = false;
                }
            } else {
                current.push(c);
            }
        } else {
            if c == '"' {
                in_quotes = true;
            } else if c == ',' {
                fields.push(current.clone());
                current.clear();
            } else {
                current.push(c);
            }
        }
        i += 1;
    }
    fields.push(current);
    fields
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
     .replace('<', "&lt;")
     .replace('>', "&gt;")
     .replace('"', "&quot;")
     .replace('\'', "&apos;")
}

fn extract_attr(tag: &str, name: &str) -> Option<String> {
    let pattern = format!("{}=\"", name);
    if let Some(start) = tag.find(&pattern) {
        let val_start = start + pattern.len();
        if let Some(end) = tag[val_start..].find('"') {
            return Some(tag[val_start..val_start + end].to_string());
        }
    }
    let pattern2 = format!("{}='", name);
    if let Some(start) = tag.find(&pattern2) {
        let val_start = start + pattern2.len();
        if let Some(end) = tag[val_start..].find('\'') {
            return Some(tag[val_start..val_start + end].to_string());
        }
    }
    None
}

// ============================================================
// 路由构建
// ============================================================

// ============================================================
// 收藏夹导入导出 API
// ============================================================

/// GET /api/admin/rss/folders/{id}/export — 导出收藏夹内订阅源为 CSV
pub async fn admin_export_folder_sources_csv(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> impl IntoResponse {
    let db = state.db.lock().unwrap();
    let mut csv = String::from("title,url,site_url,feed_type,category,enabled,fetch_enabled\n");

    if let Ok(mut stmt) = db.prepare(
        "SELECT s.title, s.url, s.site_url, s.feed_type, s.category, s.enabled, s.fetch_enabled
         FROM rss_sources s
         INNER JOIN rss_folder_items fi ON s.id = fi.source_id
         WHERE fi.folder_id = ?1
         ORDER BY s.created_at DESC"
    ) {
        if let Ok(rows) = stmt.query_map(params![id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, i64>(5)?,
                row.get::<_, i64>(6)?,
            ))
        }) {
            for row in rows.flatten() {
                let enabled = if row.5 == 1 { "true" } else { "false" };
                let fetch_enabled = if row.6 == 1 { "true" } else { "false" };
                csv.push_str(&format!("\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\"\n",
                    row.0.replace('"', "\"\""), row.1.replace('"', "\"\""),
                    row.2.replace('"', "\"\""), row.3.replace('"', "\"\""),
                    row.4.replace('"', "\"\""), enabled, fetch_enabled));
            }
        }
    }

    (
        [(axum::http::header::CONTENT_TYPE, "text/csv; charset=utf-8"),
         (axum::http::header::CONTENT_DISPOSITION, "attachment; filename=\"folder_sources.csv\"")],
        csv,
    )
}

/// POST /api/admin/rss/folders/{id}/import — 导入 CSV 到收藏夹
pub async fn admin_import_folder_sources_csv(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(folder_id): axum::extract::Path<i64>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let mut file_data = Vec::new();

    while let Some(field) = multipart.next_field().await.map_err(|_| StatusCode::BAD_REQUEST)? {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" || name.is_empty() {
            let data = field.bytes().await.map_err(|_| StatusCode::BAD_REQUEST)?;
            file_data = data.to_vec();
            break;
        }
    }

    if file_data.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let content = String::from_utf8(file_data).map_err(|_| StatusCode::BAD_REQUEST)?;
    let db = state.db.lock().unwrap();
    let mut imported = 0;

    for (i, line) in content.lines().enumerate() {
        if i == 0 { continue; } // skip header
        let fields = parse_csv_line(line);
        if fields.len() < 2 { continue; }
        let title = fields[0].clone();
        let url = fields[1].clone();
        let site_url = fields.get(2).cloned().unwrap_or_default();
        let feed_type = fields.get(3).cloned().unwrap_or_else(|| "rss2".to_string());
        let category = fields.get(4).cloned().unwrap_or_default();
        let enabled = fields.get(5).cloned().unwrap_or_else(|| "true".to_string()) != "false";
        let fetch_enabled = fields.get(6).cloned().unwrap_or_else(|| "true".to_string()) != "false";

        let enabled_val = if enabled { 1 } else { 0 };
        let fetch_enabled_val = if fetch_enabled { 1 } else { 0 };

        // Insert or ignore source
        let _ = db.execute(
            "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, category, enabled, fetch_enabled, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now'), datetime('now'))",
            params![title, url, site_url, feed_type, category, enabled_val, fetch_enabled_val],
        );

        // Get source id
        if let Ok(source_id) = db.query_row(
            "SELECT id FROM rss_sources WHERE url = ?1",
            params![url],
            |row| row.get::<_, i64>(0),
        ) {
            // Add to folder
            let _ = db.execute(
                "INSERT OR IGNORE INTO rss_folder_items (folder_id, source_id, created_at) VALUES (?1, ?2, datetime('now'))",
                params![folder_id, source_id],
            );
            imported += 1;
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "imported": imported })))
}

/// GET /api/admin/rss/folders/{id}/export/opml — 导出收藏夹内订阅源为 OPML
pub async fn admin_export_folder_sources_opml(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> impl IntoResponse {
    let db = state.db.lock().unwrap();
    let mut opml = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">\n<head><title>Zebra RSS Folder Sources</title></head>\n<body>\n");

    if let Ok(mut stmt) = db.prepare(
        "SELECT s.title, s.url, s.site_url
         FROM rss_sources s
         INNER JOIN rss_folder_items fi ON s.id = fi.source_id
         WHERE fi.folder_id = ?1
         ORDER BY s.created_at DESC"
    ) {
        if let Ok(rows) = stmt.query_map(params![id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?))
        }) {
            for row in rows.flatten() {
                opml.push_str(&format!("  <outline text=\"{}\" title=\"{}\" type=\"rss\" xmlUrl=\"{}\" htmlUrl=\"{}\"/>\n",
                    xml_escape(&row.0), xml_escape(&row.0), xml_escape(&row.1), xml_escape(&row.2)));
            }
        }
    }

    opml.push_str("</body>\n</opml>");

    (
        [(axum::http::header::CONTENT_TYPE, "text/xml; charset=utf-8"),
         (axum::http::header::CONTENT_DISPOSITION, "attachment; filename=\"folder_sources.opml\"")],
        opml,
    )
}

/// POST /api/admin/rss/folders/{id}/import/opml — 导入 OPML 到收藏夹
pub async fn admin_import_folder_sources_opml(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(folder_id): axum::extract::Path<i64>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let mut file_data = Vec::new();

    while let Some(field) = multipart.next_field().await.map_err(|_| StatusCode::BAD_REQUEST)? {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" || name.is_empty() {
            let data = field.bytes().await.map_err(|_| StatusCode::BAD_REQUEST)?;
            file_data = data.to_vec();
            break;
        }
    }

    if file_data.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let content = String::from_utf8(file_data).map_err(|_| StatusCode::BAD_REQUEST)?;
    let db = state.db.lock().unwrap();
    let mut imported = 0;

    // Simple OPML parsing - find all <outline> with xmlUrl
    let mut pos = 0;
    while let Some(start) = content[pos..].find("<outline") {
        let abs_start = pos + start;
        if let Some(end) = content[abs_start..].find('>') {
            let tag = &content[abs_start..abs_start + end + 1];
            pos = abs_start + end + 1;

            if let Some(url) = extract_attr(tag, "xmlUrl").or_else(|| extract_attr(tag, "xmlurl")) {
                let title = extract_attr(tag, "title")
                    .or_else(|| extract_attr(tag, "text"))
                    .unwrap_or_else(|| url.clone());
                let html_url = extract_attr(tag, "htmlUrl")
                    .or_else(|| extract_attr(tag, "htmlurl"))
                    .unwrap_or_default();

                if url.is_empty() { continue; }

                // Insert or ignore source
                let _ = db.execute(
                    "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, enabled, created_at, updated_at)
                     VALUES (?1, ?2, ?3, 'rss2', 1, datetime('now'), datetime('now'))",
                    params![title, url, html_url],
                );

                // Get source id
                if let Ok(source_id) = db.query_row(
                    "SELECT id FROM rss_sources WHERE url = ?1",
                    params![url],
                    |row| row.get::<_, i64>(0),
                ) {
                    // Add to folder
                    let _ = db.execute(
                        "INSERT OR IGNORE INTO rss_folder_items (folder_id, source_id, created_at) VALUES (?1, ?2, datetime('now'))",
                        params![folder_id, source_id],
                    );
                    imported += 1;
                }
            }
        } else {
            break;
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "imported": imported })))
}

// ============================================================
// 文章 API（S3：分页 / 详情 / 未读汇总 / 手动 sync / 状态）
// ============================================================

#[derive(Debug, Serialize)]
pub struct RssArticleOut {
    pub id: i64,
    pub source_id: i64,
    pub guid: String,
    pub title: String,
    pub link: String,
    pub author: String,
    pub summary: String,
    pub content: String,
    pub published_at: Option<String>,
    pub is_read: bool,
    pub is_starred: bool,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RssArticleQuery {
    pub page: Option<i64>,
    pub size: Option<i64>,
    pub source_id: Option<i64>,
    pub search: Option<String>,
    /// read=unread | read | all
    pub read: Option<String>,
    pub starred: Option<bool>,
    /// days>0 时仅返回最近 N 天入库的文章(created_at >= datetime('now','-N days')),
    /// 由服务端按 UTC 计算,避免客户端时区偏差
    pub days: Option<i64>,
    /// format=csv 时返回 CSV 导出（后台）
    pub format: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PaginatedRssArticles {
    pub data: Vec<RssArticleOut>,
    pub total: i64,
    pub page: i64,
    pub size: i64,
}

const ARTICLE_COLS: &str = "id, source_id, guid, title, link, author, summary, content, published_at, is_read, is_starred, created_at, updated_at";

fn row_to_article(row: &rusqlite::Row) -> rusqlite::Result<RssArticleOut> {
    Ok(RssArticleOut {
        id: row.get(0)?,
        source_id: row.get(1)?,
        guid: row.get(2)?,
        title: row.get(3)?,
        link: row.get(4)?,
        author: row.get(5)?,
        summary: row.get(6)?,
        content: row.get(7)?,
        published_at: row.get(8)?,
        is_read: row.get::<_, i64>(9)? == 1,
        is_starred: row.get::<_, i64>(10)? == 1,
        created_at: row.get(11)?,
        updated_at: row.get(12)?,
    })
}

/// 构造 FTS5 MATCH 表达式：按空格分词，每个词加引号防语法错误
fn fts_match_expr(keyword: &str) -> String {
    keyword
        .trim()
        .split_whitespace()
        .map(|t| format!("\"{}\"", t.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(" AND ")
}

/// 通用文章查询（公开与管理共用）
fn query_articles(
    db: &rusqlite::Connection,
    q: &RssArticleQuery,
) -> (Vec<RssArticleOut>, i64) {
    let page = q.page.unwrap_or(1).max(1);
    let size = q.size.unwrap_or(20).min(100);
    let offset = (page - 1) * size;

    // 动态 WHERE 条件
    let mut conditions: Vec<String> = Vec::new();
    let mut params: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if let Some(sid) = q.source_id {
        conditions.push("source_id = ?".to_string());
        params.push(Box::new(sid));
    }
    match q.read.as_deref() {
        Some("unread") => {
            conditions.push("is_read = 0".to_string());
        }
        Some("read") => {
            conditions.push("is_read = 1".to_string());
        }
        _ => {}
    }
    if let Some(st) = q.starred {
        if st {
            conditions.push("is_starred = 1".to_string());
        }
    }
    // days>0:仅返回最近 N 天入库的文章,由服务端按 UTC 计算,避免客户端时区偏差
    if let Some(days) = q.days {
        if days > 0 {
            conditions.push("created_at >= datetime('now', ?)".to_string());
            params.push(Box::new(format!("-{} days", days)));
        }
    }

    let search = q.search.as_deref().unwrap_or("").trim();
    let use_fts = !search.is_empty();

    let where_sql = if use_fts {
        let mut s = String::new();
        if !conditions.is_empty() {
            s.push_str(" AND ");
            s.push_str(&conditions.join(" AND "));
        }
        s
    } else if !conditions.is_empty() {
        format!(" WHERE {}", conditions.join(" AND "))
    } else {
        String::new()
    };

    // 总数
    let total: i64 = if use_fts {
        let fts = fts_match_expr(search);
        let sql = format!(
            "SELECT COUNT(*) FROM rss_articles_fts f JOIN rss_articles a ON a.id = f.rowid WHERE rss_articles_fts MATCH ?1{}",
            where_sql
        );
        let mut stmt = match db.prepare(&sql) {
            Ok(s) => s,
            Err(_) => return (Vec::new(), 0),
        };
        let mut all_params: Vec<&dyn rusqlite::types::ToSql> = vec![&fts];
        for p in &params {
            all_params.push(p.as_ref() as &dyn rusqlite::types::ToSql);
        }
        stmt.query_row(all_params.as_slice(), |r| r.get(0)).unwrap_or(0)
    } else {
        let sql = format!("SELECT COUNT(*) FROM rss_articles{}", where_sql);
        match db.prepare(&sql) {
            Ok(mut stmt) => {
                let refs: Vec<&dyn rusqlite::types::ToSql> = params
                    .iter()
                    .map(|p| p.as_ref() as &dyn rusqlite::types::ToSql)
                    .collect();
                stmt.query_row(refs.as_slice(), |r| r.get(0)).unwrap_or(0)
            }
            Err(_) => 0,
        }
    };

    // 数据行
    let (sql, query_params): (String, Vec<Box<dyn rusqlite::types::ToSql>>) = if use_fts {
        let fts = fts_match_expr(search);
        let sql = format!(
            "SELECT a.id, a.source_id, a.guid, a.title, a.link, a.author, a.summary, a.content, a.published_at, a.is_read, a.is_starred, a.created_at, a.updated_at \
             FROM rss_articles_fts f JOIN rss_articles a ON a.id = f.rowid \
             WHERE rss_articles_fts MATCH ?1{} ORDER BY a.created_at DESC, a.id DESC LIMIT ? OFFSET ?",
            where_sql
        );
        let mut qp: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        qp.push(Box::new(fts));
        qp.extend(params);
        qp.push(Box::new(size));
        qp.push(Box::new(offset));
        (sql, qp)
    } else {
        let sql = format!(
            "SELECT {} FROM rss_articles{} ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?",
            ARTICLE_COLS, where_sql
        );
        let mut qp: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        qp.extend(params);
        qp.push(Box::new(size));
        qp.push(Box::new(offset));
        (sql, qp)
    };

    let mut articles = Vec::new();
    if let Ok(mut stmt) = db.prepare(&sql) {
        let refs: Vec<&dyn rusqlite::types::ToSql> = query_params
            .iter()
            .map(|p| p.as_ref() as &dyn rusqlite::types::ToSql)
            .collect();
        if let Ok(rows) = stmt.query_map(refs.as_slice(), row_to_article) {
            articles = rows.filter_map(|r| r.ok()).collect();
        }
    }

    (articles, total)
}

/// GET /api/rss/articles — 文章分页（?source_id=&page=&size=&search=&read=&starred=）
pub async fn list_rss_articles(
    State(state): State<Arc<RssDb>>,
    axum::extract::Query(q): axum::extract::Query<RssArticleQuery>,
) -> Json<PaginatedRssArticles> {
    let db = state.db.lock().unwrap();
    let (data, total) = query_articles(&db, &q);
    Json(PaginatedRssArticles {
        data,
        total,
        page: q.page.unwrap_or(1).max(1),
        size: q.size.unwrap_or(20).min(100),
    })
}

/// GET /api/rss/articles/unread — 各源未读数汇总
pub async fn rss_unread_summary(State(state): State<Arc<RssDb>>) -> Json<serde_json::Value> {
    let db = state.db.lock().unwrap();
    let sql = r#"
        SELECT s.id, s.title, COUNT(a.id) AS unread
        FROM rss_sources s
        LEFT JOIN rss_articles a ON a.source_id = s.id AND a.is_read = 0
        WHERE s.enabled = 1
        GROUP BY s.id
        ORDER BY s.id
    "#;
    let mut items = Vec::new();
    if let Ok(mut stmt) = db.prepare(sql) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok(serde_json::json!({
                "source_id": r.get::<_, i64>(0)?,
                "title": r.get::<_, String>(1)?,
                "unread": r.get::<_, i64>(2)?,
            }))
        }) {
            items = rows.filter_map(|r| r.ok()).collect();
        }
    }
    let total: i64 = items.iter().map(|v| v["unread"].as_i64().unwrap_or(0)).sum();
    Json(serde_json::json!({ "success": true, "data": items, "total_unread": total }))
}

/// GET /api/rss/articles/{id} — 文章详情（含 content 全文）
pub async fn get_rss_article(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    let sql = format!("SELECT {} FROM rss_articles WHERE id = ?1", ARTICLE_COLS);
    let result = db
        .prepare(&sql)
        .and_then(|mut stmt| stmt.query_row(rusqlite::params![id], row_to_article))
        .map_err(|_| StatusCode::NOT_FOUND)?;
    Ok(Json(serde_json::json!({ "success": true, "data": result })))
}

/// GET /api/rss/sync/status — 抓取状态汇总
pub async fn rss_sync_status(State(state): State<Arc<RssDb>>) -> Json<serde_json::Value> {
    let db = state.db.lock().unwrap();
    let total: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_sources WHERE enabled = 1", [], |r| r.get(0))
        .unwrap_or(0);
    let stale_secs = state.fetch_stale_min * 60;
    let pending: i64 = db
        .query_row(
            r#"SELECT COUNT(*) FROM rss_sources s
               LEFT JOIN rss_sync_state st ON st.source_id = s.id
               WHERE s.enabled = 1
                 AND (st.last_fetch_at IS NULL OR st.last_fetch_at = ''
                      OR strftime('%s','now') - strftime('%s', st.last_fetch_at) >= ?1)"#,
            rusqlite::params![stale_secs],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let failed: i64 = db
        .query_row(
            r#"SELECT COUNT(*) FROM rss_sync_state WHERE consecutive_failures >= 5"#,
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let last_fetch: Option<String> = db
        .query_row("SELECT MAX(last_fetch_at) FROM rss_sync_state", [], |r| r.get(0))
        .unwrap_or(None);

    let mut sources = Vec::new();
    if let Ok(mut stmt) = db.prepare(
        r#"SELECT s.id, s.title, s.url, st.last_fetch_at, st.consecutive_failures, st.last_error
           FROM rss_sources s LEFT JOIN rss_sync_state st ON st.source_id = s.id
           WHERE s.enabled = 1 ORDER BY s.id"#,
    ) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok(serde_json::json!({
                "source_id": r.get::<_, i64>(0)?,
                "title": r.get::<_, String>(1)?,
                "url": r.get::<_, String>(2)?,
                "last_fetch_at": r.get::<_, Option<String>>(3)?,
                "consecutive_failures": r.get::<_, i64>(4)?,
                "last_error": r.get::<_, Option<String>>(5)?,
            }))
        }) {
            sources = rows.filter_map(|r| r.ok()).collect();
        }
    }

    Json(serde_json::json!({
        "success": true,
        "data": {
            "total": total,
            "pending": pending,
            "failed": failed,
            "last_fetch_at": last_fetch,
            "scan_interval_min": state.scan_interval_min,
            "fetch_stale_min": state.fetch_stale_min,
            "sources": sources,
        }
    }))
}

/// POST /api/rss/sync — 手动触发立即抓取（标记全部启用源过期并唤醒 worker）
pub async fn rss_manual_sync(State(state): State<Arc<RssDb>>) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    let _ = db.execute(
        r#"UPDATE rss_sync_state SET last_fetch_at = NULL
           WHERE source_id IN (SELECT id FROM rss_sources WHERE enabled = 1)"#,
        [],
    );
    drop(db);
    state.wake.notify_one();
    Ok(Json(serde_json::json!({ "success": true, "message": "sync triggered" })))
}

/// POST /api/admin/rss/sync — 后台强制全量抓取
pub async fn admin_rss_force_sync(State(state): State<Arc<RssDb>>) -> Result<Json<serde_json::Value>, StatusCode> {
    rss_manual_sync(State(state.clone())).await
}

/// GET /api/admin/rss/articles — 后台文章列表（同公开接口，含全部状态）
/// 支持 ?format=csv 导出（用于管理后台「导出 CSV」按钮）
pub async fn admin_list_rss_articles(
    State(state): State<Arc<RssDb>>,
    axum::extract::Query(q): axum::extract::Query<RssArticleQuery>,
) -> impl IntoResponse {
    let db = state.db.lock().unwrap();
    let (data, total) = query_articles(&db, &q);

    if q.format.as_deref() == Some("csv") {
        let mut csv = String::from("id,source_id,guid,title,link,author,published_at,is_read,is_starred,created_at\n");
        for a in &data {
            csv.push_str(&format!(
                "\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\"\n",
                a.id,
                a.source_id,
                csv_esc(&a.guid),
                csv_esc(&a.title),
                csv_esc(&a.link),
                csv_esc(&a.author),
                a.published_at.as_deref().unwrap_or(""),
                if a.is_read { "1" } else { "0" },
                if a.is_starred { "1" } else { "0" },
                a.created_at.as_deref().unwrap_or(""),
            ));
        }
        return (
            [(axum::http::header::CONTENT_TYPE, "text/csv; charset=utf-8"),
             (axum::http::header::CONTENT_DISPOSITION, "attachment; filename=\"rss_articles.csv\"")],
            csv,
        )
            .into_response();
    }

    Json(PaginatedRssArticles {
        data,
        total,
        page: q.page.unwrap_or(1).max(1),
        size: q.size.unwrap_or(20).min(100),
    })
    .into_response()
}

fn csv_esc(s: &str) -> String {
    s.replace('"', "\"\"")
}

/// DELETE /api/admin/rss/articles/{id} — 后台删除文章
pub async fn admin_delete_rss_article(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();
    let deleted = db
        .execute("DELETE FROM rss_articles WHERE id = ?1", rusqlite::params![id])
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({ "success": true, "deleted": deleted })))
}

/// 后台新增/编辑文章的请求体
#[derive(Debug, Deserialize)]
pub struct ArticleUpsertRequest {
    pub source_id: i64,
    #[serde(default)]
    pub guid: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub link: String,
    #[serde(default)]
    pub author: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub content: String,
    #[serde(default)]
    pub published_at: Option<String>,
    #[serde(default)]
    pub is_read: bool,
    #[serde(default)]
    pub is_starred: bool,
}

/// POST /api/admin/rss/articles — 后台新增文章
pub async fn admin_create_rss_article(
    State(state): State<Arc<RssDb>>,
    Json(body): Json<ArticleUpsertRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();

    // 校验 source_id 必须存在
    let src_exists: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM rss_sources WHERE id = ?1",
            rusqlite::params![body.source_id],
            |r| r.get(0),
        )
        .unwrap_or(0);
    if src_exists == 0 {
        return Err(StatusCode::BAD_REQUEST);
    }

    db.execute(
        "INSERT INTO rss_articles (source_id, guid, title, link, author, summary, content, published_at, is_read, is_starred, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, datetime('now'), datetime('now'))",
        rusqlite::params![
            body.source_id,
            body.guid,
            body.title,
            body.link,
            body.author,
            body.summary,
            body.content,
            body.published_at,
            if body.is_read { 1 } else { 0 },
            if body.is_starred { 1 } else { 0 },
        ],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let id = db.last_insert_rowid();
    Ok(Json(serde_json::json!({ "success": true, "data": { "id": id } })))
}

/// PUT /api/admin/rss/articles/{id} — 后台编辑文章
pub async fn admin_update_rss_article(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<ArticleUpsertRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();

    let changed = db
        .execute(
            "UPDATE rss_articles SET source_id = ?1, guid = ?2, title = ?3, link = ?4,
             author = ?5, summary = ?6, content = ?7, published_at = ?8,
             is_read = ?9, is_starred = ?10, updated_at = datetime('now') WHERE id = ?11",
            rusqlite::params![
                body.source_id,
                body.guid,
                body.title,
                body.link,
                body.author,
                body.summary,
                body.content,
                body.published_at,
                if body.is_read { 1 } else { 0 },
                if body.is_starred { 1 } else { 0 },
                id,
            ],
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if changed == 0 {
        return Err(StatusCode::NOT_FOUND);
    }
    Ok(Json(serde_json::json!({ "success": true })))
}

/// POST /api/admin/rss/articles/import — 后台 CSV 导入文章
/// CSV 列：source_id,guid,title,link,author,summary,content,published_at,is_read,is_starred
pub async fn admin_import_rss_articles_csv(
    State(state): State<Arc<RssDb>>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let mut file_data = Vec::new();
    while let Some(field) = multipart.next_field().await.map_err(|_| StatusCode::BAD_REQUEST)? {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" || name.is_empty() {
            file_data = field.bytes().await.map_err(|_| StatusCode::BAD_REQUEST)?.to_vec();
            break;
        }
    }
    if file_data.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let content = String::from_utf8(file_data).map_err(|_| StatusCode::BAD_REQUEST)?;
    let db = state.db.lock().unwrap();
    let mut imported = 0;
    let mut skipped = 0;

    for (i, line) in content.lines().enumerate() {
        if i == 0 { continue; } // skip header
        let fields = parse_csv_line(line);
        if fields.len() < 3 { continue; }
        let source_id: i64 = match fields[0].trim().parse() {
            Ok(v) => v,
            Err(_) => { skipped += 1; continue; }
        };
        let guid = fields[1].clone();
        let title = fields[2].clone();
        let link = fields.get(3).cloned().unwrap_or_default();
        let author = fields.get(4).cloned().unwrap_or_default();
        let summary = fields.get(5).cloned().unwrap_or_default();
        let content2 = fields.get(6).cloned().unwrap_or_default();
        let published_at = fields.get(7).cloned().filter(|s| !s.is_empty());
        let is_read = fields.get(8).map(|s| s == "1").unwrap_or(false);
        let is_starred = fields.get(9).map(|s| s == "1").unwrap_or(false);

        let result = db.execute(
            "INSERT OR IGNORE INTO rss_articles
                (source_id, guid, title, link, author, summary, content, published_at, is_read, is_starred, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, datetime('now'), datetime('now'))",
            rusqlite::params![
                source_id, guid, title, link, author, summary, content2, published_at,
                if is_read { 1 } else { 0 }, if is_starred { 1 } else { 0 },
            ],
        );
        match result {
            Ok(n) if n > 0 => imported += 1,
            _ => skipped += 1,
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "imported": imported, "skipped": skipped })))
}

/// PATCH /api/rss/articles/{id}/state — 同步已读/星标状态（客户端 server 模式）
#[derive(Debug, Deserialize)]
pub struct ArticleStateRequest {
    #[serde(default)]
    pub read: Option<bool>,
    #[serde(default)]
    pub starred: Option<bool>,
}

pub async fn update_rss_article_state(
    State(state): State<Arc<RssDb>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<ArticleStateRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let db = state.db.lock().unwrap();

    let exists: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM rss_articles WHERE id = ?1",
            rusqlite::params![id],
            |r| r.get(0),
        )
        .unwrap_or(0);
    if exists == 0 {
        return Err(StatusCode::NOT_FOUND);
    }

    match (body.read, body.starred) {
        (Some(read), Some(starred)) => {
            let _ = db.execute(
                "UPDATE rss_articles SET is_read = ?1, is_starred = ?2, updated_at = datetime('now') WHERE id = ?3",
                rusqlite::params![if read { 1 } else { 0 }, if starred { 1 } else { 0 }, id],
            );
        }
        (Some(read), None) => {
            let _ = db.execute(
                "UPDATE rss_articles SET is_read = ?1, updated_at = datetime('now') WHERE id = ?2",
                rusqlite::params![if read { 1 } else { 0 }, id],
            );
        }
        (None, Some(starred)) => {
            let _ = db.execute(
                "UPDATE rss_articles SET is_starred = ?1, updated_at = datetime('now') WHERE id = ?2",
                rusqlite::params![if starred { 1 } else { 0 }, id],
            );
        }
        (None, None) => return Err(StatusCode::BAD_REQUEST),
    }

    Ok(Json(serde_json::json!({ "success": true })))
}

/// GET /api/admin/rss/stats — RSS 统计分析（纯 SQL 聚合）
pub async fn admin_rss_stats(State(state): State<Arc<RssDb>>) -> Json<serde_json::Value> {
    let db = state.db.lock().unwrap();

    // ===== 总体汇总 =====
    let source_total: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_sources", [], |r| r.get(0))
        .unwrap_or(0);
    let source_enabled: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_sources WHERE enabled = 1", [], |r| r.get(0))
        .unwrap_or(0);
    let source_fetch_off: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_sources WHERE fetch_enabled = 0", [], |r| r.get(0))
        .unwrap_or(0);
    let article_total: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_articles", [], |r| r.get(0))
        .unwrap_or(0);
    let article_unread: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_articles WHERE is_read = 0", [], |r| r.get(0))
        .unwrap_or(0);
    let article_starred: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_articles WHERE is_starred = 1", [], |r| r.get(0))
        .unwrap_or(0);
    let folder_total: i64 = db
        .query_row("SELECT COUNT(*) FROM rss_folders", [], |r| r.get(0))
        .unwrap_or(0);

    // ===== 来源排行（文章数 Top 15 + 未读数）=====
    let mut source_ranking: Vec<serde_json::Value> = Vec::new();
    if let Ok(mut stmt) = db.prepare(
        r#"SELECT s.id, s.title, COUNT(a.id) AS cnt,
                  SUM(CASE WHEN a.is_read = 0 THEN 1 ELSE 0 END) AS unread
           FROM rss_sources s
           LEFT JOIN rss_articles a ON a.source_id = s.id
           GROUP BY s.id
           ORDER BY cnt DESC LIMIT 15"#,
    ) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok(serde_json::json!({
                "source_id": r.get::<_, i64>(0)?,
                "title": r.get::<_, String>(1)?,
                "count": r.get::<_, i64>(2)?,
                "unread": r.get::<_, Option<i64>>(3)?.unwrap_or(0),
            }))
        }) {
            source_ranking = rows.filter_map(|r| r.ok()).collect();
        }
    }

    // ===== 发文趋势（近 30 天，按日期分组）=====
    let mut daily_trend: Vec<serde_json::Value> = Vec::new();
    if let Ok(mut stmt) = db.prepare(
        r#"SELECT date(created_at) AS day, COUNT(*) AS cnt
           FROM rss_articles
           WHERE created_at >= date('now', '-29 days')
           GROUP BY day ORDER BY day"#,
    ) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok(serde_json::json!({
                "date": r.get::<_, String>(0)?,
                "count": r.get::<_, i64>(1)?,
            }))
        }) {
            daily_trend = rows.filter_map(|r| r.ok()).collect();
        }
    }

    // ===== 分类分布（按源的 category 分组，统计文章数）=====
    let mut category_dist: Vec<serde_json::Value> = Vec::new();
    if let Ok(mut stmt) = db.prepare(
        r#"SELECT COALESCE(NULLIF(s.category, ''), '未分类') AS cat, COUNT(a.id) AS cnt
           FROM rss_sources s
           LEFT JOIN rss_articles a ON a.source_id = s.id
           GROUP BY cat ORDER BY cnt DESC"#,
    ) {
        if let Ok(rows) = stmt.query_map([], |r| {
            Ok(serde_json::json!({
                "category": r.get::<_, String>(0)?,
                "count": r.get::<_, i64>(1)?,
            }))
        }) {
            category_dist = rows.filter_map(|r| r.ok()).collect();
        }
    }

    // ===== 抓取健康 =====
    let pending: i64 = db
        .query_row(
            r#"SELECT COUNT(*) FROM rss_sources s
               LEFT JOIN rss_sync_state st ON st.source_id = s.id
               WHERE s.enabled = 1 AND s.fetch_enabled = 1
                 AND (st.last_fetch_at IS NULL OR st.last_fetch_at = ''
                      OR strftime('%s','now') - strftime('%s', st.last_fetch_at) >= 1800)"#,
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let failed: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM rss_sync_state WHERE consecutive_failures >= 5",
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let last_fetch: Option<String> = db
        .query_row("SELECT MAX(last_fetch_at) FROM rss_sync_state", [], |r| r.get(0))
        .unwrap_or(None);

    Json(serde_json::json!({
        "success": true,
        "data": {
            "totals": {
                "sources": source_total,
                "sources_enabled": source_enabled,
                "sources_fetch_off": source_fetch_off,
                "articles": article_total,
                "unread": article_unread,
                "starred": article_starred,
                "folders": folder_total,
            },
            "source_ranking": source_ranking,
            "daily_trend": daily_trend,
            "category_distribution": category_dist,
            "fetch_health": {
                "total": source_enabled,
                "pending": pending,
                "failed": failed,
                "last_fetch_at": last_fetch,
            },
        }
    }))
}

pub fn rss_routes() -> Router<Arc<RssDb>> {
    Router::new()
        // 公开 API
        .route("/api/rss/sources", get(list_rss_sources))
        .route("/api/rss/folders", get(list_rss_folders))
        .route("/api/rss/folders/{id}/sources", get(list_folder_sources))
        // 文章 API（S3）
        .route("/api/rss/articles", get(list_rss_articles))
        .route("/api/rss/articles/unread", get(rss_unread_summary))
        .route("/api/rss/articles/{id}", get(get_rss_article))
        .route("/api/rss/articles/{id}/state", axum::routing::patch(update_rss_article_state))
        .route("/api/rss/sync", post(rss_manual_sync))
        .route("/api/rss/sync/status", get(rss_sync_status))
        // 后台文章与同步管理（S3）
        .route("/api/admin/rss/articles", get(admin_list_rss_articles))
        .route("/api/admin/rss/articles", post(admin_create_rss_article))
        .route("/api/admin/rss/articles/import", post(admin_import_rss_articles_csv))
        .route("/api/admin/rss/articles/{id}", axum::routing::put(admin_update_rss_article))
        .route("/api/admin/rss/articles/{id}", axum::routing::delete(admin_delete_rss_article))
        .route("/api/admin/rss/sync", post(admin_rss_force_sync))
        // 统计分析（S5）
        .route("/api/admin/rss/stats", get(admin_rss_stats))
        // 管理 API
        .route("/api/admin/rss", get(admin_rss_page))
        .route("/api/admin/rss/sources", get(admin_list_rss_sources))
        .route("/api/admin/rss/sources", post(admin_create_rss_source))
        .route("/api/admin/rss/sources/{id}", axum::routing::put(admin_update_rss_source))
        .route("/api/admin/rss/sources/{id}", axum::routing::delete(admin_delete_rss_source))
        .route("/api/admin/rss/sources/batch-delete", post(admin_batch_delete_rss_sources))
        .route("/api/admin/rss/sources/export", get(admin_export_rss_sources_csv))
        .route("/api/admin/rss/sources/import", post(admin_import_rss_sources_csv))
        .route("/api/admin/rss/sources/export/opml", get(admin_export_rss_sources_opml))
        .route("/api/admin/rss/sources/import/opml", post(admin_import_rss_sources_opml))
        // 收藏夹管理 API
        .route("/api/admin/rss/folders", get(list_rss_folders))
        .route("/api/admin/rss/folders", post(admin_create_folder))
        .route("/api/admin/rss/folders/{id}", axum::routing::put(admin_update_folder))
        .route("/api/admin/rss/folders/{id}", axum::routing::delete(admin_delete_folder))
        .route("/api/admin/rss/folders/{id}/sources", get(admin_folder_sources))
        .route("/api/admin/rss/folders/{id}/sources", post(admin_add_source_to_folder))
        .route("/api/admin/rss/folders/{id}/sources/batch", post(admin_batch_add_sources_to_folder))
        .route("/api/admin/rss/folders/{id}/sources/{source_id}", axum::routing::delete(admin_remove_source_from_folder))
        .route("/api/admin/rss/folders/{id}/sources/batch-delete", post(admin_batch_remove_sources_from_folder))
        // 收藏夹导入导出 API
        .route("/api/admin/rss/folders/{id}/export", get(admin_export_folder_sources_csv))
        .route("/api/admin/rss/folders/{id}/import", post(admin_import_folder_sources_csv))
        .route("/api/admin/rss/folders/{id}/export/opml", get(admin_export_folder_sources_opml))
        .route("/api/admin/rss/folders/{id}/import/opml", post(admin_import_folder_sources_opml))
}
