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
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_rss_sources_url ON rss_sources(url);
            CREATE INDEX IF NOT EXISTS idx_rss_sources_enabled ON rss_sources(enabled);
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
        ").expect("Failed to create RSS tables");

        Self { db: Mutex::new(conn) }
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
        "SELECT s.id, s.title, s.url, s.site_url, s.feed_type, s.category, s.enabled, s.created_at, s.updated_at
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
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
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
        "SELECT s.id, s.title, s.url, s.site_url, s.feed_type, s.category, s.enabled, s.created_at, s.updated_at
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
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
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

    let mut sql = "SELECT id, title, url, site_url, feed_type, category, enabled, created_at, updated_at FROM rss_sources WHERE enabled = 1".to_string();

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
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
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

    let mut sql = "SELECT id, title, url, site_url, feed_type, category, enabled, created_at, updated_at FROM rss_sources".to_string();
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
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
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

    db.execute(
        "INSERT INTO rss_sources (title, url, site_url, feed_type, category, enabled, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, datetime('now'), datetime('now'))",
        params![body.title, body.url, body.site_url, body.feed_type, body.category, enabled],
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

    db.execute(
        "UPDATE rss_sources SET title = ?1, url = ?2, site_url = ?3, feed_type = ?4,
         category = ?5, enabled = ?6, updated_at = datetime('now') WHERE id = ?7",
        params![body.title, body.url, body.site_url, body.feed_type, body.category, enabled, id],
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
    let mut csv = String::from("title,url,site_url,feed_type,category,enabled\n");

    if let Ok(mut stmt) = db.prepare("SELECT title, url, site_url, feed_type, category, enabled FROM rss_sources ORDER BY created_at DESC") {
        if let Ok(rows) = stmt.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, i64>(5)?,
            ))
        }) {
            for row in rows.flatten() {
                let enabled = if row.5 == 1 { "true" } else { "false" };
                csv.push_str(&format!("\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\"\n",
                    row.0.replace('"', "\"\""), row.1.replace('"', "\"\""),
                    row.2.replace('"', "\"\""), row.3.replace('"', "\"\""),
                    row.4.replace('"', "\"\""), enabled));
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

        let enabled_val = if enabled { 1 } else { 0 };
        let result = db.execute(
            "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, category, enabled, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, datetime('now'), datetime('now'))",
            params![title, url, site_url, feed_type, category, enabled_val],
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
    let mut csv = String::from("title,url,site_url,feed_type,category,enabled\n");

    if let Ok(mut stmt) = db.prepare(
        "SELECT s.title, s.url, s.site_url, s.feed_type, s.category, s.enabled
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
            ))
        }) {
            for row in rows.flatten() {
                let enabled = if row.5 == 1 { "true" } else { "false" };
                csv.push_str(&format!("\"{}\",\"{}\",\"{}\",\"{}\",\"{}\",\"{}\"\n",
                    row.0.replace('"', "\"\""), row.1.replace('"', "\"\""),
                    row.2.replace('"', "\"\""), row.3.replace('"', "\"\""),
                    row.4.replace('"', "\"\""), enabled));
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

        let enabled_val = if enabled { 1 } else { 0 };

        // Insert or ignore source
        let _ = db.execute(
            "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, category, enabled, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, datetime('now'), datetime('now'))",
            params![title, url, site_url, feed_type, category, enabled_val],
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

pub fn rss_routes() -> Router<Arc<RssDb>> {
    Router::new()
        // 公开 API
        .route("/api/rss/sources", get(list_rss_sources))
        .route("/api/rss/folders", get(list_rss_folders))
        .route("/api/rss/folders/{id}/sources", get(list_folder_sources))
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
