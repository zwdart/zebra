// #![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]  // 调试时暂时关闭

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, Multipart, State},
    http::{Request, StatusCode},
    response::{Html, Response},
    routing::{get, post},
    body::Body,
};
use http_body_util::BodyExt;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use chrono::Local;
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::ServeDir;
use tower::{Layer, Service};
use std::task::{Context, Poll};
use std::pin::Pin;
use std::future::Future;

// ============================================================
// 配置
// ============================================================

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub port: Option<u16>,
    pub domain: Option<String>,
    pub data_dir: Option<String>,
    pub static_dir: Option<String>,
    /// HTTP log max bytes per field (headers/body). 0 = unlimited. Default 2048.
    pub log_max_bytes: Option<usize>,
}

impl Config {
    pub fn load() -> Self {
        let config_path = PathBuf::from("config.toml");
        if config_path.exists() {
            match std::fs::read_to_string(&config_path) {
                Ok(content) => match toml::from_str(&content) {
                    Ok(config) => {
                        eprintln!("[config] Loaded config.toml");
                        return config;
                    }
                    Err(e) => {
                        eprintln!("[config] Failed to parse config.toml: {}", e);
                    }
                },
                Err(e) => {
                    eprintln!("[config] Failed to read config.toml: {}", e);
                }
            }
        }
        eprintln!("[config] No config.toml found, using defaults");
        Config {
            port: None,
            domain: None,
            data_dir: None,
            static_dir: None,
            log_max_bytes: None,
        }
    }

    pub fn port(&self) -> u16 {
        self.port.unwrap_or(8686)
    }

    pub fn domain(&self) -> &str {
        self.domain.as_deref().unwrap_or("zebra.dart.xin")
    }

    pub fn data_dir(&self) -> &str {
        self.data_dir.as_deref().unwrap_or("runtimes")
    }

    pub fn static_dir(&self) -> &str {
        self.static_dir.as_deref().unwrap_or("static")
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            port: None,
            domain: None,
            data_dir: None,
            static_dir: None,
            log_max_bytes: None,
        }
    }
}

// ============================================================
// 数据结构
// ============================================================

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct VersionInfo {
    pub id: i64,
    pub platform: String,
    pub version: String,
    pub version_code: i64,
    #[serde(rename = "type")]
    pub version_type: String,
    pub download_url: String,
    pub force_update: bool,
    pub changelog: String,
    pub file_size: u64,
    pub file_hash: String,
    pub release_date: String,
    pub min_supported_version: Option<String>,
    pub file_name: String,
}

#[derive(Deserialize)]
pub struct VersionQuery {
    pub current_version: String,
    pub version_code: Option<i64>,
    pub platform: String,
}

#[derive(Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub service: String,
    pub version: String,
    pub uptime_secs: u64,
    pub started_at: String,
    pub pid: u32,
}

// ============================================================
// 发现数据结构
// ============================================================

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct DiscoveryItem {
    pub id: i64,
    #[serde(rename = "type")]
    pub item_type: i32,       // 0=官方, 1=推荐, 2=广告
    pub name: String,
    pub description: String,
    pub url: String,
    pub icon_url: Option<String>,
    pub clicks: i64,
    pub sort_order: i32,
    pub enabled: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct DiscoveryQuery {
    pub page: Option<u32>,
    pub size: Option<u32>,
    pub sort: Option<String>,    // "time" or "hot"
    #[serde(rename = "type")]
    pub item_type: Option<i32>,  // filter by type
}

#[derive(Deserialize)]
pub struct DiscoveryCreateRequest {
    #[serde(rename = "type")]
    pub item_type: i32,
    pub name: String,
    pub description: String,
    pub url: String,
    pub icon_url: Option<String>,
    pub sort_order: Option<i32>,
    pub enabled: Option<bool>,
}

#[derive(Deserialize)]
pub struct DiscoveryUpdateRequest {
    #[serde(rename = "type")]
    pub item_type: Option<i32>,
    pub name: Option<String>,
    pub description: Option<String>,
    pub url: Option<String>,
    pub icon_url: Option<String>,
    pub clicks: Option<i64>,
    pub sort_order: Option<i32>,
    pub enabled: Option<bool>,
}

#[derive(Serialize)]
pub struct PaginatedResponse<T: Serialize> {
    pub success: bool,
    pub data: Option<T>,
    pub total: u64,
    pub page: u32,
    pub size: u32,
    pub error: Option<String>,
}

struct AppState {
    db: Mutex<Connection>,
    uploads_dir: String,
    domain: String,
    start_time: Instant,
    started_at: String,
    pid: u32,
}

// ============================================================
// 日志系统
// ============================================================

/// 日志文件路径
fn log_file_path() -> PathBuf {
    let data_dir = std::env::var("ZEBRA_DATA_DIR").unwrap_or_else(|_| "runtimes".to_string());
    let log_dir = PathBuf::from(data_dir).join("logs");
    std::fs::create_dir_all(&log_dir).ok();
    let date = Local::now().format("%Y-%m-%d").to_string();
    log_dir.join(format!("api-{}.log", date))
}

/// 写入日志
fn write_log(entry: &str) {
    use std::io::Write;
    let path = log_file_path();
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .unwrap();
    writeln!(file, "{}", entry).ok();
}

/// 格式化请求头（总长度限制，超出截断）
fn format_headers(headers: &http::HeaderMap, max_bytes: usize) -> String {
    let mut result = String::new();
    let mut total = 0;
    for (key, value) in headers.iter() {
        if let Ok(v) = value.to_str() {
            let line = format!("    {}: {}\n", key, v);
            if max_bytes > 0 && total + line.len() > max_bytes {
                result.push_str(&format!("    ... (truncated, {} bytes total)\n", total));
                break;
            }
            result.push_str(&line);
            total += line.len();
        }
    }
    result
}

/// 日志中间件 - 记录完整的请求和响应
#[derive(Clone)]
struct LoggingLayer {
    log_max_bytes: usize,
}

impl<S> Layer<S> for LoggingLayer {
    type Service = LoggingService<S>;
    fn layer(&self, inner: S) -> Self::Service {
        LoggingService { inner, log_max_bytes: self.log_max_bytes }
    }
}

#[derive(Clone)]
struct LoggingService<S> {
    inner: S,
    log_max_bytes: usize,
}

impl<S> Service<Request<Body>> for LoggingService<S>
where
    S: Service<Request<Body>, Response = Response<Body>> + Send + Clone + 'static,
    S::Future: Send + 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<Body>) -> Self::Future {
        let method = req.method().clone();
        let uri = req.uri().clone();
        let headers = req.headers().clone();
        let start = Instant::now();
        let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();

        // 提取请求头
        let remote_addr = headers
            .get("x-forwarded-for")
            .or_else(|| headers.get("x-real-ip"))
            .and_then(|v| v.to_str().ok())
            .unwrap_or("-")
            .to_string();

        let log_max = self.log_max_bytes;
        let user_agent = headers
            .get("user-agent")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("-")
            .to_string();

        let content_type = headers
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("-")
            .to_string();

        let content_length = headers
            .get("content-length")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("0")
            .to_string();

        // 记录请求头
        let mut request_log = format!(
            "[{}] ===== REQUEST =====\n\
             {} {} HTTP/1.1\n\
             Host: {}\n\
             Remote: {}\n\
             User-Agent: {}\n\
             Content-Type: {}\n\
             Content-Length: {}\n\
             Headers:\n{}",
            timestamp,
            method, uri,
            headers.get("host").and_then(|v| v.to_str().ok()).unwrap_or("-"),
            remote_addr,
            user_agent,
            content_type,
            content_length,
            format_headers(&headers, log_max)
        );

        let mut inner = self.inner.clone();
        Box::pin(async move {
            // 读取请求体
            let (parts, body) = req.into_parts();
            let uri_path = parts.uri.path().to_string();
            let body_bytes = body.collect().await.map(|c| c.to_bytes()).unwrap_or_default();
            let body_len = body_bytes.len();

            // 记录请求体（multipart 上传跳过 body 日志，避免大文件撑爆日志）
            let is_multipart = content_type.contains("multipart/form-data");

            if !is_multipart {
                // 截断过长的请求体
                let body_str = if log_max > 0 && body_len > log_max {
                    let truncated = String::from_utf8_lossy(&body_bytes[..log_max]);
                    format!("{}...(truncated, {} bytes total)", truncated, body_len)
                } else {
                    String::from_utf8_lossy(&body_bytes).to_string()
                };

                // 记录请求体
                if !body_str.contains("truncated") || body_len <= log_max {
                    if !body_str.is_empty() {
                        request_log.push_str(&format!("Body:\n{}\n", body_str));
                    }
                } else {
                    request_log.push_str(&format!("Body: (truncated, {} bytes total)\n", body_len));
                }
            } else {
                request_log.push_str(&format!("Body: (multipart, {} bytes total, skipped)\n", body_len));
            }
            request_log.push_str("======================\n");
            write_log(&request_log);
            eprintln!("{}", request_log);

            // 重建请求
            let req = Request::from_parts(parts, Body::from(body_bytes));

            // 调用下游服务
            let response = inner.call(req).await?;
            let elapsed = start.elapsed().as_millis();
            let status = response.status();
            let resp_headers = response.headers().clone();

            // 读取响应体
            let (resp_parts, resp_body) = response.into_parts();
            let resp_body_bytes = resp_body.collect().await.map(|c| c.to_bytes()).unwrap_or_default();
            let resp_body_str = String::from_utf8_lossy(&resp_body_bytes).to_string();

            // 记录响应
            let mut response_log = format!(
                "[{}] ===== RESPONSE =====\n\
                 {} {} {} ({}ms)\n\
                 Headers:\n{}",
                Local::now().format("%Y-%m-%d %H:%M:%S%.3f"),
                method, uri, status.as_u16(), elapsed,
                format_headers(&resp_headers, log_max)
            );

            // 跳过静态文件/上传文件的 body 日志（二进制内容无价值）
            let skip_body = uri_path.starts_with("/api/uploads/") || uri_path.starts_with("/static/");

            if !resp_body_str.is_empty() && !skip_body {
                // 截断过长的响应体
                if log_max > 0 && resp_body_str.len() > log_max {
                    let truncated = &resp_body_str[..log_max];
                    response_log.push_str(&format!("Body: (truncated, {} bytes total)\n", resp_body_str.len()));
                    response_log.push_str(&format!("{}\n", truncated));
                } else {
                    response_log.push_str(&format!("Body:\n{}\n", resp_body_str));
                }
            } else if !resp_body_str.is_empty() && skip_body {
                response_log.push_str(&format!("Body: (binary, {} bytes total, skipped)\n", resp_body_bytes.len()));
            }
            response_log.push_str("=======================\n");
            write_log(&response_log);
            eprintln!("{}", response_log);

            // 重建响应
            Ok(Response::from_parts(resp_parts, Body::from(resp_body_bytes)))
        })
    }
}

// ============================================================
// 数据库
// ============================================================

fn init_db(db: &Connection) {
    db.execute_batch(
        "CREATE TABLE IF NOT EXISTS versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            platform TEXT NOT NULL,
            version TEXT NOT NULL,
            version_code INTEGER NOT NULL DEFAULT 0,
            type TEXT NOT NULL DEFAULT 'file',
            download_url TEXT NOT NULL DEFAULT '',
            force_update INTEGER NOT NULL DEFAULT 0,
            changelog TEXT NOT NULL DEFAULT '',
            file_size INTEGER NOT NULL DEFAULT 0,
            file_hash TEXT NOT NULL DEFAULT '',
            release_date TEXT NOT NULL DEFAULT '',
            min_supported_version TEXT,
            file_name TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_versions_platform ON versions(platform);
        CREATE INDEX IF NOT EXISTS idx_versions_platform_version ON versions(platform, version_code DESC);

        CREATE TABLE IF NOT EXISTS discoveries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type INTEGER NOT NULL DEFAULT 0,
            name TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            icon_url TEXT DEFAULT '',
            clicks INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_discoveries_type ON discoveries(type);
        CREATE INDEX IF NOT EXISTS idx_discoveries_enabled ON discoveries(enabled);
        CREATE INDEX IF NOT EXISTS idx_discoveries_sort_order ON discoveries(sort_order);
        "
    ).expect("Failed to create table");

    // 迁移：为已有数据添加 type 字段（如果不存在）
    let has_type: bool = db.prepare("SELECT type FROM versions LIMIT 1").is_ok();
    if !has_type {
        db.execute_batch("ALTER TABLE versions ADD COLUMN type TEXT NOT NULL DEFAULT 'file'").ok();
    }
}

fn db_get_latest(db: &Connection, platform: &str) -> Option<VersionInfo> {
    db.query_row(
        "SELECT id, platform, version, version_code, type, download_url, force_update,
                changelog, file_size, file_hash, release_date, min_supported_version, file_name
         FROM versions WHERE platform = ?1
         ORDER BY version_code DESC LIMIT 1",
        params![platform],
        |row| {
            Ok(VersionInfo {
                id: row.get(0)?,
                platform: row.get(1)?,
                version: row.get(2)?,
                version_code: row.get(3)?,
                version_type: row.get(4)?,
                download_url: row.get(5)?,
                force_update: row.get::<_, i64>(6)? != 0,
                changelog: row.get(7)?,
                file_size: row.get(8)?,
                file_hash: row.get(9)?,
                release_date: row.get(10)?,
                min_supported_version: row.get(11)?,
                file_name: row.get(12)?,
            })
        },
    ).ok()
}


fn db_get_by_id(db: &Connection, id: i64) -> Option<VersionInfo> {
    db.query_row(
        "SELECT id, platform, version, version_code, type, download_url, force_update,
                changelog, file_size, file_hash, release_date, min_supported_version, file_name
         FROM versions WHERE id = ?1",
        params![id],
        |row| {
            Ok(VersionInfo {
                id: row.get(0)?,
                platform: row.get(1)?,
                version: row.get(2)?,
                version_code: row.get(3)?,
                version_type: row.get(4)?,
                download_url: row.get(5)?,
                force_update: row.get::<_, i64>(6)? != 0,
                changelog: row.get(7)?,
                file_size: row.get(8)?,
                file_hash: row.get(9)?,
                release_date: row.get(10)?,
                min_supported_version: row.get(11)?,
                file_name: row.get(12)?,
            })
        },
    ).ok()
}

// ============================================================
// 版本比较
// ============================================================

fn version_greater(a: &str, b: &str) -> bool {
    let parse = |v: &str| -> Vec<i64> {
        v.split('.').filter_map(|s| s.parse().ok()).collect()
    };
    let a_parts = parse(a);
    let b_parts = parse(b);
    let max_len = a_parts.len().max(b_parts.len());
    for i in 0..max_len {
        let a_val = a_parts.get(i).unwrap_or(&0);
        let b_val = b_parts.get(i).unwrap_or(&0);
        if a_val > b_val { return true; }
        if a_val < b_val { return false; }
    }
    false
}

fn compute_hash(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    format!("sha256:{}", hex::encode(hasher.finalize()))
}

/// 规范化下载 URL：相对路径补上域名和 /api/ 前缀，绝对路径原样返回
fn normalize_download_url(url: &str, domain: &str) -> String {
    if url.starts_with("http://") || url.starts_with("https://") {
        return url.to_string();
    }
    // 数据库存的是 /uploads/xxx，补上 /api/ 前缀和域名
    let path = url.strip_prefix('/').unwrap_or(url);
    format!("https://{}{}/{}", domain, "/api", path)
}

/// 从文件名猜测版本号，如 zebra-ssh-1.2.0.exe -> Some("1.2.0")
fn guess_version_from_filename(name: &str) -> Option<String> {
    let name = name.split('.').next().unwrap_or(name);
    // 找最后一段数字.数字.数字
    let parts: Vec<&str> = name.split('-').collect();
    // 从后往前找版本号模式
    for part in parts.iter().rev() {
        let digits: Vec<&str> = part.split('.').collect();
        if digits.len() >= 2 && digits.iter().all(|d| d.chars().all(|c| c.is_ascii_digit())) {
            return Some(digits.join("."));
        }
    }
    None
}

// ============================================================
// 发现数据 - 数据库操作
// ============================================================

fn db_discovery_get_paginated(
    db: &Connection,
    page: u32,
    size: u32,
    sort: &str,
    item_type: Option<i32>,
) -> (Vec<DiscoveryItem>, u64) {
    let offset = (page.saturating_sub(1)) * size;
    let (order_clause, count_params, list_params) = match sort {
        "hot" => {
            let mut cp: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
            let mut lp: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
            if let Some(t) = item_type {
                cp.push(Box::new(t));
                lp.push(Box::new(t));
                (
                    "WHERE enabled = 1 AND type = ?".to_string(),
                    cp,
                    lp,
                )
            } else {
                ("".to_string(), cp, lp)
            }
        }
        _ => {
            // "time" or default
            let mut cp: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
            let mut lp: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
            if let Some(t) = item_type {
                cp.push(Box::new(t));
                lp.push(Box::new(t));
                (
                    "WHERE enabled = 1 AND type = ?".to_string(),
                    cp,
                    lp,
                )
            } else {
                ("".to_string(), cp, lp)
            }
        }
    };

    let where_enabled = if order_clause.is_empty() {
        "WHERE enabled = 1"
    } else {
        &order_clause
    };

    // Count total
    let count_sql = format!("SELECT COUNT(*) FROM discoveries {}", where_enabled);
    let total: u64 = {
        let mut count_params_iter = count_params.iter();
        db.query_row(&count_sql, rusqlite::params_from_iter(count_params_iter.by_ref()), |row| row.get(0)).unwrap_or(0)
    };

    // Fetch page
    let order = if sort == "hot" {
        "ORDER BY clicks DESC, sort_order ASC, id DESC"
    } else {
        "ORDER BY created_at DESC, sort_order ASC, id DESC"
    };
    let list_sql = format!(
        "SELECT id, type, name, description, url, icon_url, clicks, sort_order, enabled, created_at, updated_at
         FROM discoveries {} {} LIMIT ? OFFSET ?",
        where_enabled, order
    );

    let mut all_params: Vec<Box<dyn rusqlite::types::ToSql>> = list_params;
    all_params.push(Box::new(size as i64));
    all_params.push(Box::new(offset as i64));

    let mut stmt = match db.prepare(&list_sql) {
        Ok(s) => s,
        Err(_) => return (vec![], total),
    };
    let params_ref: Vec<&dyn rusqlite::types::ToSql> = all_params.iter().map(|p| p.as_ref()).collect();
    let rows = stmt.query_map(params_ref.as_slice(), |row| {
        Ok(DiscoveryItem {
            id: row.get(0)?,
            item_type: row.get(1)?,
            name: row.get(2)?,
            description: row.get(3)?,
            url: row.get(4)?,
            icon_url: row.get(5)?,
            clicks: row.get(6)?,
            sort_order: row.get(7)?,
            enabled: row.get::<_, i64>(8)? != 0,
            created_at: row.get(9)?,
            updated_at: row.get(10)?,
        })
    }).unwrap();

    let items: Vec<DiscoveryItem> = rows.filter_map(|r| r.ok()).collect();
    (items, total)
}

fn db_discovery_get_random(db: &Connection) -> Option<DiscoveryItem> {
    db.query_row(
        "SELECT id, type, name, description, url, icon_url, clicks, sort_order, enabled, created_at, updated_at
         FROM discoveries WHERE enabled = 1 ORDER BY RANDOM() LIMIT 1",
        [],
        |row| {
            Ok(DiscoveryItem {
                id: row.get(0)?,
                item_type: row.get(1)?,
                name: row.get(2)?,
                description: row.get(3)?,
                url: row.get(4)?,
                icon_url: row.get(5)?,
                clicks: row.get(6)?,
                sort_order: row.get(7)?,
                enabled: row.get::<_, i64>(8)? != 0,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
            })
        },
    ).ok()
}

fn db_discovery_get_by_id(db: &Connection, id: i64) -> Option<DiscoveryItem> {
    db.query_row(
        "SELECT id, type, name, description, url, icon_url, clicks, sort_order, enabled, created_at, updated_at
         FROM discoveries WHERE id = ?1",
        params![id],
        |row| {
            Ok(DiscoveryItem {
                id: row.get(0)?,
                item_type: row.get(1)?,
                name: row.get(2)?,
                description: row.get(3)?,
                url: row.get(4)?,
                icon_url: row.get(5)?,
                clicks: row.get(6)?,
                sort_order: row.get(7)?,
                enabled: row.get::<_, i64>(8)? != 0,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
            })
        },
    ).ok()
}

fn db_discovery_increment_clicks(db: &Connection, id: i64) {
    db.execute(
        "UPDATE discoveries SET clicks = clicks + 1, updated_at = datetime('now') WHERE id = ?1",
        params![id],
    ).ok();
}

fn db_discovery_get_all(db: &Connection) -> Vec<DiscoveryItem> {
    let mut stmt = db
        .prepare(
            "SELECT id, type, name, description, url, icon_url, clicks, sort_order, enabled, created_at, updated_at
             FROM discoveries ORDER BY sort_order ASC, id DESC",
        )
        .unwrap();
    let rows = stmt
        .query_map([], |row| {
            Ok(DiscoveryItem {
                id: row.get(0)?,
                item_type: row.get(1)?,
                name: row.get(2)?,
                description: row.get(3)?,
                url: row.get(4)?,
                icon_url: row.get(5)?,
                clicks: row.get(6)?,
                sort_order: row.get(7)?,
                enabled: row.get::<_, i64>(8)? != 0,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
            })
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

fn db_discovery_create(db: &Connection, req: &DiscoveryCreateRequest) -> Result<DiscoveryItem, String> {
    let sort_order = req.sort_order.unwrap_or(0);
    let enabled = req.enabled.unwrap_or(true);
    db.execute(
        "INSERT INTO discoveries (type, name, description, url, icon_url, clicks, sort_order, enabled)
         VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6, ?7)",
        params![
            req.item_type,
            req.name,
            req.description,
            req.url,
            req.icon_url.as_deref().unwrap_or(""),
            sort_order,
            enabled as i64,
        ],
    ).map_err(|e| e.to_string())?;
    let id = db.last_insert_rowid();
    db_discovery_get_by_id(db, id).ok_or_else(|| "Failed to retrieve created item".to_string())
}

fn db_discovery_update(db: &Connection, id: i64, req: &DiscoveryUpdateRequest) -> Result<DiscoveryItem, String> {
    if db_discovery_get_by_id(db, id).is_none() {
        return Err("Discovery item not found".to_string());
    }

    let mut updates = Vec::new();
    let mut param_values: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if let Some(v) = req.item_type {
        updates.push("type = ?"); param_values.push(Box::new(v));
    }
    if let Some(ref v) = req.name {
        updates.push("name = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(ref v) = req.description {
        updates.push("description = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(ref v) = req.url {
        updates.push("url = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(ref v) = req.icon_url {
        updates.push("icon_url = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(v) = req.clicks {
        updates.push("clicks = ?"); param_values.push(Box::new(v));
    }
    if let Some(v) = req.sort_order {
        updates.push("sort_order = ?"); param_values.push(Box::new(v));
    }
    if let Some(v) = req.enabled {
        updates.push("enabled = ?"); param_values.push(Box::new(v as i64));
    }

    if updates.is_empty() {
        return db_discovery_get_by_id(db, id).ok_or_else(|| "Item not found".to_string());
    }

    updates.push("updated_at = datetime('now')");
    let sql = format!("UPDATE discoveries SET {} WHERE id = ?", updates.join(", "));
    let mut stmt = db.prepare(&sql).map_err(|e| e.to_string())?;
    param_values.push(Box::new(id));
    let params: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|p| p.as_ref()).collect();
    stmt.execute(params.as_slice()).map_err(|e| e.to_string())?;

    db_discovery_get_by_id(db, id).ok_or_else(|| "Failed to retrieve updated item".to_string())
}

fn db_discovery_delete(db: &Connection, id: i64) -> Result<(), String> {
    if db_discovery_get_by_id(db, id).is_none() {
        return Err("Discovery item not found".to_string());
    }
    db.execute("DELETE FROM discoveries WHERE id = ?1", params![id]).map_err(|e| e.to_string())?;
    Ok(())
}

// ============================================================
// API Handlers - 版本查询
// ============================================================

/// POST /api/version
/// Body: { "current_version": "1.0.0", "version_code": 100, "platform": "windows" }
async fn check_version(
    State(state): State<Arc<AppState>>,
    Json(query): Json<VersionQuery>,
) -> Result<Json<VersionInfo>, (StatusCode, Json<ApiResponse<()>>)> {
    let valid_platforms = ["windows", "linux", "macos", "android", "ios"];
    if !valid_platforms.contains(&query.platform.as_str()) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid platform: {}", query.platform)),
            }),
        ));
    }

    let db = state.db.lock().unwrap();
    match db_get_latest(&db, &query.platform) {
        Some(info) => {
            // 优先使用 version_code 比较，否则使用版本号字符串比较
            let has_update = if let Some(client_version_code) = query.version_code {
                info.version_code > client_version_code
            } else {
                version_greater(&info.version, &query.current_version)
            };

            if has_update {
                let normalized = VersionInfo {
                    download_url: normalize_download_url(&info.download_url, &state.domain),
                    ..info
                };
                Ok(Json(normalized))
            } else {
                // 已是最新
                Ok(Json(VersionInfo {
                    id: 0,
                    platform: query.platform.clone(),
                    version: query.current_version.clone(),
                    version_code: 0,
                    version_type: "file".to_string(),
                    download_url: String::new(),
                    force_update: false,
                    changelog: String::new(),
                    file_size: 0,
                    file_hash: String::new(),
                    release_date: String::new(),
                    min_supported_version: None,
                    file_name: String::new(),
                }))
            }
        }
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("No version found for platform: {}", query.platform)),
            }),
        )),
    }
}

/// GET /api/version/latest?platform=windows
async fn get_latest(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> Result<Json<VersionInfo>, (StatusCode, Json<ApiResponse<()>>)> {
    let platform = query.get("platform").map(|s| s.as_str()).unwrap_or("windows");
    let db = state.db.lock().unwrap();
    match db_get_latest(&db, platform) {
        Some(info) => {
            let normalized = VersionInfo {
                download_url: normalize_download_url(&info.download_url, &state.domain),
                ..info
            };
            Ok(Json(normalized))
        }
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("No version found for platform: {}", platform)),
            }),
        )),
    }
}

/// GET /api/health
async fn health_check(
    State(state): State<Arc<AppState>>,
) -> Json<HealthResponse> {
    let uptime = state.start_time.elapsed().as_secs();
    Json(HealthResponse {
        status: "ok".to_string(),
        service: "zebra-update-api".to_string(),
        version: "1.0.0".to_string(),
        uptime_secs: uptime,
        started_at: state.started_at.clone(),
        pid: state.pid,
    })
}

// ============================================================
// Admin API Handlers
// ============================================================

/// GET /admin/api/versions - 获取所有版本
async fn admin_list_versions(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> Json<serde_json::Value> {
    let page: u32 = query.get("page").and_then(|v| v.parse().ok()).unwrap_or(1).max(1);
    let size: u32 = query.get("size").and_then(|v| v.parse().ok()).unwrap_or(20).min(100);
    let platform = query.get("platform").map(|s| s.as_str());

    let db = state.db.lock().unwrap();
    let offset = (page.saturating_sub(1)) * size;

    // Count total
    let (count_sql, count_params): (String, Vec<Box<dyn rusqlite::types::ToSql>>) = if let Some(p) = platform {
        ("SELECT COUNT(*) FROM versions WHERE platform = ?".to_string(), vec![Box::new(p.to_string())])
    } else {
        ("SELECT COUNT(*) FROM versions".to_string(), vec![])
    };
    let total: u64 = {
        let mut iter = count_params.iter();
        db.query_row(&count_sql, rusqlite::params_from_iter(iter.by_ref()), |row| row.get(0)).unwrap_or(0)
    };

    // Fetch page
    let (where_clause, mut list_params): (String, Vec<Box<dyn rusqlite::types::ToSql>>) = if let Some(p) = platform {
        ("WHERE platform = ?".to_string(), vec![Box::new(p.to_string())])
    } else {
        ("".to_string(), vec![])
    };
    let sql = format!(
        "SELECT id, platform, version, version_code, type, download_url, force_update,
                changelog, file_size, file_hash, release_date, min_supported_version, file_name
         FROM versions {} ORDER BY platform, version_code DESC LIMIT ? OFFSET ?",
        where_clause
    );
    list_params.push(Box::new(size as i64));
    list_params.push(Box::new(offset as i64));

    let mut stmt = db.prepare(&sql).unwrap();
    let params_ref: Vec<&dyn rusqlite::types::ToSql> = list_params.iter().map(|p| p.as_ref()).collect();
    let rows = stmt.query_map(params_ref.as_slice(), |row| {
        Ok(VersionInfo {
            id: row.get(0)?,
            platform: row.get(1)?,
            version: row.get(2)?,
            version_code: row.get(3)?,
            version_type: row.get(4)?,
            download_url: row.get(5)?,
            force_update: row.get::<_, i64>(6)? != 0,
            changelog: row.get(7)?,
            file_size: row.get(8)?,
            file_hash: row.get(9)?,
            release_date: row.get(10)?,
            min_supported_version: row.get(11)?,
            file_name: row.get(12)?,
        })
    }).unwrap();

    let versions: Vec<VersionInfo> = rows.filter_map(|r| r.ok()).collect();
    Json(serde_json::json!({
        "success": true,
        "data": versions,
        "total": total,
        "page": page,
        "size": size,
        "error": null
    }))
}

/// POST /admin/api/upload - 上传文件或添加URL
async fn admin_upload(
    State(state): State<Arc<AppState>>,
    mut multipart: Multipart,
) -> Result<Json<ApiResponse<VersionInfo>>, (StatusCode, Json<ApiResponse<()>>)> {
    let mut file_name = String::new();
    let mut file_data: Vec<u8> = Vec::new();
    let mut platform = String::new();
    let mut version = String::new();
    let mut version_code_input = String::new();
    let mut version_type = "file".to_string();
    let mut external_url = String::new();
    let mut changelog = String::new();
    let mut force_update = false;
    let mut min_supported_version = String::new();

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        eprintln!("Multipart field error: {}", e);
        (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> {
                success: false,
                data: None,
                error: Some(format!("Failed to read multipart field: {}", e)),
            }),
        )
    })? {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "file" => {
                file_name = field.file_name().unwrap_or("unknown").to_string();
                file_data = field.bytes().await.map_err(|e| {
                    eprintln!("File read error: {}", e);
                    (
                        StatusCode::BAD_REQUEST,
                        Json(ApiResponse::<()> {
                            success: false,
                            data: None,
                            error: Some(format!("Failed to read file data: {}", e)),
                        }),
                    )
                })?.to_vec();
            }
            "platform" => {
                platform = field.text().await.unwrap_or_default();
            }
            "version" => {
                version = field.text().await.unwrap_or_default();
            }
            "version_code" => {
                version_code_input = field.text().await.unwrap_or_default();
            }
            "type" => {
                version_type = field.text().await.unwrap_or_default();
            }
            "external_url" => {
                external_url = field.text().await.unwrap_or_default();
            }
            "changelog" => {
                changelog = field.text().await.unwrap_or_default();
            }
            "force_update" => {
                force_update = field.text().await.unwrap_or_default() == "true";
            }
            "min_supported_version" => {
                min_supported_version = field.text().await.unwrap_or_default();
            }
            _ => {}
        }
    }

    // URL类型不需要文件
    if version_type == "url" {
        if external_url.is_empty() {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ApiResponse {
                    success: false,
                    data: None,
                    error: Some("URL type requires external_url".to_string()),
                }),
            ));
        }
    } else if file_data.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("No file uploaded".to_string()),
            }),
        ));
    }

    let valid_platforms = ["windows", "linux", "macos", "android", "ios"];
    if !valid_platforms.contains(&platform.as_str()) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid platform: {}", platform)),
            }),
        ));
    }

    // 自动推断版本号
    if version.is_empty() {
        if let Some(v) = guess_version_from_filename(&file_name) {
            version = v;
        }
    }
    if version.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Version is required (or set in filename)".to_string()),
            }),
        ));
    }

    // version_code: 用户提供则使用，否则用数据库自增 ID
    let use_custom_version_code = !version_code_input.is_empty();
    let version_code: i64 = if use_custom_version_code {
        version_code_input.parse().unwrap_or(0)
    } else {
        0 // 占位，插入后用 id 更新
    };

    // 根据类型处理
    let (download_url, file_hash, file_size);
    if version_type == "url" {
        download_url = external_url.clone();
        file_hash = String::new();
        file_size = 0;
    } else {
        // 计算 hash
        file_hash = compute_hash(&file_data);
        file_size = file_data.len() as u64;
        // 保存文件
        let uploads_dir = std::path::Path::new(&state.uploads_dir);
        std::fs::create_dir_all(uploads_dir).ok();
        let save_path = uploads_dir.join(&file_name);
        std::fs::write(&save_path, &file_data).map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()> {
                    success: false,
                    data: None,
                    error: Some(format!("Failed to save file: {}", e)),
                }),
            )
        })?;
        download_url = format!("/uploads/{}", file_name);
    }

    // 插入数据库
    let db = state.db.lock().unwrap();
    let min_ver = if min_supported_version.is_empty() { None } else { Some(min_supported_version.as_str()) };
    db.execute(
        "INSERT INTO versions (platform, version, version_code, type, download_url, force_update,
                              changelog, file_size, file_hash, release_date, min_supported_version, file_name)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, datetime('now', 'localtime'), ?10, ?11)",
        params![
            platform,
            version,
            version_code,
            version_type,
            download_url,
            force_update as i64,
            changelog,
            file_size,
            file_hash,
            min_ver,
            file_name,
        ],
    ).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()> {
                success: false,
                data: None,
                error: Some(format!("Database error: {}", e)),
            }),
        )
    })?;

    let id = db.last_insert_rowid();

    // 如果没有提供 version_code，使用自增 ID 作为 version_code
    if !use_custom_version_code {
        db.execute(
            "UPDATE versions SET version_code = ?1 WHERE id = ?1",
            params![id],
        ).ok();
    }

    let info = db_get_by_id(&db, id).unwrap();

    Ok(Json(ApiResponse {
        success: true,
        data: Some(info),
        error: None,
    }))
}

/// PUT /admin/api/versions/:id - 更新版本信息
async fn admin_update_version(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<ApiResponse<VersionInfo>>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();

    // 检查存在
    if db_get_by_id(&db, id).is_none() {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Version not found".to_string()),
            }),
        ));
    }

    let mut updates = Vec::new();
    let mut param_values: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if let Some(v) = body.get("version").and_then(|v| v.as_str()) {
        updates.push("version = ?"); param_values.push(Box::new(v.to_string()));
    }
    if let Some(v) = body.get("version_code").and_then(|v| v.as_i64()) {
        updates.push("version_code = ?"); param_values.push(Box::new(v));
    }
    if let Some(v) = body.get("changelog").and_then(|v| v.as_str()) {
        updates.push("changelog = ?"); param_values.push(Box::new(v.to_string()));
    }
    if let Some(v) = body.get("force_update").and_then(|v| v.as_bool()) {
        updates.push("force_update = ?"); param_values.push(Box::new(v as i64));
    }
    if let Some(v) = body.get("min_supported_version").and_then(|v| v.as_str()) {
        updates.push("min_supported_version = ?"); param_values.push(Box::new(v.to_string()));
    }
    if let Some(v) = body.get("file_name").and_then(|v| v.as_str()) {
        updates.push("file_name = ?"); param_values.push(Box::new(v.to_string()));
    }
    if let Some(v) = body.get("download_url").and_then(|v| v.as_str()) {
        updates.push("download_url = ?"); param_values.push(Box::new(v.to_string()));
    }

    if updates.is_empty() {
        let info = db_get_by_id(&db, id).unwrap();
        return Ok(Json(ApiResponse { success: true, data: Some(info), error: None }));
    }

    updates.push("updated_at = datetime('now')");
    let sql = format!("UPDATE versions SET {} WHERE id = ?", updates.join(", "));
    let mut stmt = db.prepare(&sql).map_err(|e| {
        (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse::<()> { success: false, data: None, error: Some(e.to_string()) }))
    })?;

    param_values.push(Box::new(id));
    let params: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|p| p.as_ref()).collect();
    stmt.execute(params.as_slice()).map_err(|e| {
        (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse::<()> { success: false, data: None, error: Some(e.to_string()) }))
    })?;

    let info = db_get_by_id(&db, id).unwrap();
    Ok(Json(ApiResponse { success: true, data: Some(info), error: None }))
}

/// DELETE /admin/api/versions/:id - 删除版本
async fn admin_delete_version(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<ApiResponse<()>>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();
    let info = db_get_by_id(&db, id);
    if info.is_none() {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Version not found".to_string()),
            }),
        ));
    }

    // 删除文件
    let info = info.unwrap();
    if !info.file_name.is_empty() {
        let path = std::path::Path::new(&state.uploads_dir).join(&info.file_name);
        std::fs::remove_file(path).ok();
    }

    db.execute("DELETE FROM versions WHERE id = ?1", params![id]).ok();
    Ok(Json(ApiResponse { success: true, data: None, error: None }))
}

// ============================================================
// API Handlers - 发现数据
// ============================================================

/// GET /api/discoveries?page=1&size=10&sort=time&type=0
async fn list_discoveries(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<DiscoveryQuery>,
) -> Json<PaginatedResponse<Vec<DiscoveryItem>>> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(10).min(50);
    let sort = query.sort.as_deref().unwrap_or("time");
    let item_type = query.item_type;

    let db = state.db.lock().unwrap();
    let (items, total) = db_discovery_get_paginated(&db, page, size, sort, item_type);

    Json(PaginatedResponse {
        success: true,
        data: Some(items),
        total,
        page,
        size,
        error: None,
    })
}

/// GET /api/discoveries/random
async fn random_discovery(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DiscoveryItem>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();
    match db_discovery_get_random(&db) {
        Some(item) => Ok(Json(item)),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("No discovery items available".to_string()),
            }),
        )),
    }
}

/// POST /api/discoveries/:id/click
async fn click_discovery(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<ApiResponse<DiscoveryItem>>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();
    if db_discovery_get_by_id(&db, id).is_none() {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Discovery item not found".to_string()),
            }),
        ));
    }
    db_discovery_increment_clicks(&db, id);
    let item = db_discovery_get_by_id(&db, id).unwrap();
    Ok(Json(ApiResponse {
        success: true,
        data: Some(item),
        error: None,
    }))
}

/// GET /admin/api/discoveries - 管理后台获取所有发现数据
async fn admin_list_discoveries(
    State(state): State<Arc<AppState>>,
) -> Json<ApiResponse<Vec<DiscoveryItem>>> {
    let db = state.db.lock().unwrap();
    let items = db_discovery_get_all(&db);
    Json(ApiResponse {
        success: true,
        data: Some(items),
        error: None,
    })
}

/// POST /admin/api/discoveries - 创建发现数据
async fn admin_create_discovery(
    State(state): State<Arc<AppState>>,
    Json(body): Json<DiscoveryCreateRequest>,
) -> Result<Json<ApiResponse<DiscoveryItem>>, (StatusCode, Json<ApiResponse<()>>)> {
    if body.name.is_empty() || body.url.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Name and URL are required".to_string()),
            }),
        ));
    }
    if body.item_type < 0 || body.item_type > 2 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Type must be 0 (official), 1 (recommended), or 2 (ad)".to_string()),
            }),
        ));
    }

    let db = state.db.lock().unwrap();
    match db_discovery_create(&db, &body) {
        Ok(item) => Ok(Json(ApiResponse {
            success: true,
            data: Some(item),
            error: None,
        })),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some(e),
            }),
        )),
    }
}

/// PUT /admin/api/discoveries/:id - 更新发现数据
async fn admin_update_discovery(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<DiscoveryUpdateRequest>,
) -> Result<Json<ApiResponse<DiscoveryItem>>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();
    match db_discovery_update(&db, id, &body) {
        Ok(item) => Ok(Json(ApiResponse {
            success: true,
            data: Some(item),
            error: None,
        })),
        Err(e) => {
            let status = if e == "Discovery item not found" {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            Err((status, Json(ApiResponse {
                success: false,
                data: None,
                error: Some(e),
            })))
        }
    }
}

/// DELETE /admin/api/discoveries/:id - 删除发现数据
async fn admin_delete_discovery(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<ApiResponse<()>>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();
    match db_discovery_delete(&db, id) {
        Ok(()) => Ok(Json(ApiResponse {
            success: true,
            data: None,
            error: None,
        })),
        Err(e) => {
            let status = if e == "Discovery item not found" {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            Err((status, Json(ApiResponse {
                success: false,
                data: None,
                error: Some(e),
            })))
        }
    }
}

// ============================================================
// HTML Admin Panel
// ============================================================

// 编译时嵌入 admin.html 作为后备（确保二进制可独立运行）
const ADMIN_HTML_FALLBACK: &str = include_str!("../static/admin.html");

/// 返回管理后台 HTML
/// 优先从静态目录读取文件（支持运行时修改），不存在则使用编译时嵌入的版本
fn admin_html(static_dir: &str) -> String {
    let html_path = std::path::Path::new(static_dir).join("admin.html");
    if let Ok(content) = std::fs::read_to_string(&html_path) {
        content
    } else {
        ADMIN_HTML_FALLBACK.to_string()
    }
}

// ============================================================
// Main
// ============================================================

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();

    // 加载配置（config.toml > 命令行参数 > 默认值）
    let config = Config::load();

    let port = args.windows(2)
        .find(|w| w[0] == "--port")
        .and_then(|w| w[1].parse().ok())
        .or(config.port);

    let static_dir = args.windows(2)
        .find(|w| w[0] == "--static-dir")
        .map(|w| w[1].clone())
        .unwrap_or_else(|| config.static_dir().to_string());

    // 使用配置的数据目录存放数据库和上传文件
    let runtimes_dir = config.data_dir();
    std::env::set_var("ZEBRA_DATA_DIR", runtimes_dir);
    std::fs::create_dir_all(runtimes_dir).ok();
    let db_path = format!("{}/versions.db", runtimes_dir);
    let uploads_dir = format!("{}/uploads", runtimes_dir);
    std::fs::create_dir_all(&uploads_dir).ok();

    // 初始化数据库
    let conn = Connection::open(&db_path).expect("Failed to open database");
    init_db(&conn);

    let state = Arc::new(AppState {
        db: Mutex::new(conn),
        uploads_dir: uploads_dir.clone(),
        domain: config.domain().to_string(),
        start_time: Instant::now(),
        started_at: Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        pid: std::process::id(),
    });

    let addr = SocketAddr::from(([0, 0, 0, 0], port.unwrap_or(8686)));

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let static_dir_clone = static_dir.clone();

    let app = Router::new()
        // 公开 API
        .route("/api/version", post(check_version))
        .route("/api/version/latest", get(get_latest))
        .route("/api/health", get(health_check))
        // 发现数据 API
        .route("/api/discoveries", get(list_discoveries))
        .route("/api/discoveries/random", get(random_discovery))
        .route("/api/discoveries/{id}/click", post(click_discovery))
        // 管理后台
        .route("/api/admin", get(move || async move { Html(admin_html(&static_dir_clone)) }))
        .route("/api/admin/versions", get(admin_list_versions))
        .route("/api/admin/upload", post(admin_upload).layer(DefaultBodyLimit::max(100 * 1024 * 1024)))
        .route("/api/admin/versions/{id}", axum::routing::put(admin_update_version))
        .route("/api/admin/versions/{id}", axum::routing::delete(admin_delete_version))
        // 发现数据管理 API
        .route("/api/admin/discoveries", get(admin_list_discoveries))
        .route("/api/admin/discoveries", post(admin_create_discovery))
        .route("/api/admin/discoveries/{id}", axum::routing::put(admin_update_discovery))
        .route("/api/admin/discoveries/{id}", axum::routing::delete(admin_delete_discovery))
        // 静态文件服务（上传的文件 + static 目录）
        .nest_service("/api/uploads", ServeDir::new(&uploads_dir))
        .nest_service("/static", ServeDir::new(&static_dir))
        .layer(LoggingLayer { log_max_bytes: config.log_max_bytes.unwrap_or(2048) })
        .layer(cors)
        .with_state(state);

    println!("Zebra Update Server running on http://{}", addr);
    println!();
    println!("  Admin Panel:  http://{}/api/admin", addr);
    println!("  API Health:   http://{}/api/health", addr);
    println!("  Version API:  POST http://{}/api/version", addr);
    println!();
    println!("  Config:       config.toml");
    println!("  Data:         {}/versions.db", runtimes_dir);
    println!("  Uploads:      {}/uploads/", runtimes_dir);
    println!("  Logs:         {}/logs/api-*.log", runtimes_dir);
    println!();
    println!("  Options:");
    println!("    --port <PORT>       Server port (overrides config.toml)");
    println!("    --static-dir <DIR>  Static files directory (overrides config.toml)");
    println!();
    println!("  config.toml 示例:");
    println!("    port = 8686");
    println!("    domain = \"zebra.dart.xin\"");
    println!("    data_dir = \"runtimes\"");
    println!("    static_dir = \"static\"");
    println!();

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
