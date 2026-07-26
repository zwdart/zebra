// #![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]  // 调试时暂时关闭

pub mod rss_server;

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, Multipart, State},
    http::{Request, StatusCode},
    response::{Html, IntoResponse, Response},
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
    /// Admin login username (default: admin)
    pub admin_username: Option<String>,
    /// Admin login password (default: zebra2024)
    pub admin_password: Option<String>,
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
            admin_username: None,
            admin_password: None,
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

    pub fn admin_username(&self) -> &str {
        self.admin_username.as_deref().unwrap_or("admin")
    }

    pub fn admin_password(&self) -> &str {
        self.admin_password.as_deref().unwrap_or("zebra2024")
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
            admin_username: None,
            admin_password: None,
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
    pub unique_id: Option<String>,
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
    pub tags: Option<String>,
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
    pub search: Option<String>,  // fuzzy search on name, description, tags
}

#[derive(Deserialize)]
pub struct DiscoveryCreateRequest {
    #[serde(rename = "type")]
    pub item_type: i32,
    pub name: String,
    pub description: String,
    pub url: String,
    pub icon_url: Option<String>,
    pub tags: Option<String>,
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
    pub tags: Option<String>,
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

// ============================================================
// 博客数据结构
// ============================================================

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct BlogPost {
    pub id: i64,
    pub title: String,
    pub content: String,
    pub summary: String,
    pub tags: Option<String>,
    pub sort_order: i32,
    pub published: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct BlogCreateRequest {
    pub title: String,
    pub content: String,
    pub summary: Option<String>,
    pub tags: Option<String>,
    pub sort_order: Option<i32>,
    pub published: Option<bool>,
}

#[derive(Deserialize)]
pub struct BlogUpdateRequest {
    pub title: Option<String>,
    pub content: Option<String>,
    pub summary: Option<String>,
    pub tags: Option<String>,
    pub sort_order: Option<i32>,
    pub published: Option<bool>,
}

#[derive(Deserialize)]
pub struct BlogQuery {
    pub page: Option<u32>,
    pub size: Option<u32>,
    pub search: Option<String>,
}

// ============================================================
// 反馈数据结构
// ============================================================

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct FeedbackItem {
    pub id: i64,
    pub email: String,
    pub subject: String,
    pub description: String,
    pub platform: String,
    pub app_version: String,
    pub tags: Option<String>,
    pub created_at: String,
}

#[derive(Deserialize)]
pub struct FeedbackCreateRequest {
    pub email: String,
    pub subject: String,
    pub description: String,
    pub platform: Option<String>,
    pub app_version: Option<String>,
}

#[derive(Deserialize)]
pub struct FeedbackTagRequest {
    pub tags: String,
}

#[derive(Deserialize)]
pub struct FeedbackBatchDeleteRequest {
    pub ids: Vec<i64>,
}

#[derive(Deserialize)]
pub struct FeedbackQuery {
    pub page: Option<u32>,
    pub size: Option<u32>,
    pub search: Option<String>,
}

struct AppState {
    db: Mutex<Connection>,
    rss_db: Arc<rss_server::RssDb>,
    uploads_dir: String,
    domain: String,
    start_time: Instant,
    started_at: String,
    pid: u32,
    admin_username: String,
    admin_password: String,
    static_dir: String,
    /// Rate limiting for feedback: email -> last submit time
    feedback_rate_limit: Mutex<std::collections::HashMap<String, Instant>>,
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
                    let truncated: String = resp_body_str.chars().take(log_max).collect();
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
            tags TEXT DEFAULT '',
            clicks INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_discoveries_type ON discoveries(type);
        CREATE INDEX IF NOT EXISTS idx_discoveries_enabled ON discoveries(enabled);
        CREATE INDEX IF NOT EXISTS idx_discoveries_sort_order ON discoveries(sort_order);

        CREATE TABLE IF NOT EXISTS blog_posts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL DEFAULT '',
            content TEXT NOT NULL DEFAULT '',
            summary TEXT NOT NULL DEFAULT '',
            tags TEXT DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            published INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_blog_posts_published ON blog_posts(published);
        CREATE INDEX IF NOT EXISTS idx_blog_posts_created ON blog_posts(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_blog_posts_sort ON blog_posts(sort_order DESC, created_at DESC);

        CREATE TABLE IF NOT EXISTS app_launches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            unique_id TEXT NOT NULL DEFAULT '',
            platform TEXT NOT NULL DEFAULT '',
            app_version TEXT NOT NULL DEFAULT '',
            launched_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_app_launches_unique_id ON app_launches(unique_id);
        CREATE INDEX IF NOT EXISTS idx_app_launches_launched_at ON app_launches(launched_at DESC);

        CREATE TABLE IF NOT EXISTS feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL DEFAULT '',
            subject TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            platform TEXT NOT NULL DEFAULT '',
            app_version TEXT NOT NULL DEFAULT '',
            tags TEXT DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_feedback_created_at ON feedback(created_at DESC);
        "
    ).expect("Failed to create table");

    // 迁移：为已有数据添加 type 字段（如果不存在）
    let has_type: bool = db.prepare("SELECT type FROM versions LIMIT 1").is_ok();
    if !has_type {
        db.execute_batch("ALTER TABLE versions ADD COLUMN type TEXT NOT NULL DEFAULT 'file'").ok();
    }

    // 迁移：为已有数据添加 tags 字段（如果不存在）
    let has_tags: bool = db.prepare("SELECT tags FROM discoveries LIMIT 1").is_ok();
    if !has_tags {
        db.execute_batch("ALTER TABLE discoveries ADD COLUMN tags TEXT DEFAULT ''").ok();
    }

    // 迁移：为已有数据添加 sort_order 字段（如果不存在）
    let has_sort_order: bool = db.prepare("SELECT sort_order FROM blog_posts LIMIT 1").is_ok();
    if !has_sort_order {
        db.execute_batch("ALTER TABLE blog_posts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0").ok();
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
    search: Option<&str>,
) -> (Vec<DiscoveryItem>, u64) {
    db_discovery_get_paginated_inner(db, page, size, sort, item_type, search, true)
}

fn db_discovery_get_paginated_admin(
    db: &Connection,
    page: u32,
    size: u32,
    sort: &str,
    item_type: Option<i32>,
    search: Option<&str>,
) -> (Vec<DiscoveryItem>, u64) {
    db_discovery_get_paginated_inner(db, page, size, sort, item_type, search, false)
}

fn db_discovery_get_paginated_inner(
    db: &Connection,
    page: u32,
    size: u32,
    sort: &str,
    item_type: Option<i32>,
    search: Option<&str>,
    enabled_only: bool,
) -> (Vec<DiscoveryItem>, u64) {
    let offset = (page.saturating_sub(1)) * size;

    let mut conditions: Vec<String> = Vec::new();
    let mut params_list: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if enabled_only {
        conditions.push("enabled = 1".to_string());
    }

    if let Some(t) = item_type {
        conditions.push("type = ?".to_string());
        params_list.push(Box::new(t));
    }

    if let Some(q) = search {
        if !q.trim().is_empty() {
            let pattern = format!("%{}%", q.trim());
            conditions.push("(name LIKE ? OR description LIKE ? OR tags LIKE ?)".to_string());
            params_list.push(Box::new(pattern.clone()));
            params_list.push(Box::new(pattern.clone()));
            params_list.push(Box::new(pattern));
        }
    }

    let where_clause = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };

    // Count total
    let count_sql = format!("SELECT COUNT(*) FROM discoveries {}", where_clause);
    let count_params_list: Vec<&dyn rusqlite::types::ToSql> = params_list.iter().map(|p| p.as_ref()).collect();
    let total: u64 = db.query_row(&count_sql, count_params_list.as_slice(), |row| row.get(0)).unwrap_or(0);

    // Fetch page
    let order = if sort == "hot" {
        "ORDER BY clicks DESC, sort_order ASC, id DESC"
    } else {
        "ORDER BY created_at DESC, sort_order ASC, id DESC"
    };
    let list_sql = format!(
        "SELECT id, type, name, description, url, icon_url, tags, clicks, sort_order, enabled, created_at, updated_at
         FROM discoveries {} {} LIMIT ? OFFSET ?",
        where_clause, order
    );

    params_list.push(Box::new(size as i64));
    params_list.push(Box::new(offset as i64));

    let mut stmt = match db.prepare(&list_sql) {
        Ok(s) => s,
        Err(_) => return (vec![], total),
    };
    let params_ref: Vec<&dyn rusqlite::types::ToSql> = params_list.iter().map(|p| p.as_ref()).collect();
    let rows = stmt.query_map(params_ref.as_slice(), |row| {
        Ok(DiscoveryItem {
            id: row.get(0)?,
            item_type: row.get(1)?,
            name: row.get(2)?,
            description: row.get(3)?,
            url: row.get(4)?,
            icon_url: row.get(5)?,
            tags: row.get(6)?,
            clicks: row.get(7)?,
            sort_order: row.get(8)?,
            enabled: row.get::<_, i64>(9)? != 0,
            created_at: row.get(10)?,
            updated_at: row.get(11)?,
        })
    }).unwrap();

    let items: Vec<DiscoveryItem> = rows.filter_map(|r| r.ok()).collect();
    (items, total)
}

fn db_discovery_get_random(db: &Connection) -> Option<DiscoveryItem> {
    db.query_row(
        "SELECT id, type, name, description, url, icon_url, tags, clicks, sort_order, enabled, created_at, updated_at
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
                tags: row.get(6)?,
                clicks: row.get(7)?,
                sort_order: row.get(8)?,
                enabled: row.get::<_, i64>(9)? != 0,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
            })
        },
    ).ok()
}

fn db_discovery_get_by_id(db: &Connection, id: i64) -> Option<DiscoveryItem> {
    db.query_row(
        "SELECT id, type, name, description, url, icon_url, tags, clicks, sort_order, enabled, created_at, updated_at
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
                tags: row.get(6)?,
                clicks: row.get(7)?,
                sort_order: row.get(8)?,
                enabled: row.get::<_, i64>(9)? != 0,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
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
            "SELECT id, type, name, description, url, icon_url, tags, clicks, sort_order, enabled, created_at, updated_at
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
                tags: row.get(6)?,
                clicks: row.get(7)?,
                sort_order: row.get(8)?,
                enabled: row.get::<_, i64>(9)? != 0,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
            })
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

fn db_discovery_create(db: &Connection, req: &DiscoveryCreateRequest) -> Result<DiscoveryItem, String> {
    let sort_order = req.sort_order.unwrap_or(0);
    let enabled = req.enabled.unwrap_or(true);
    db.execute(
        "INSERT INTO discoveries (type, name, description, url, icon_url, tags, clicks, sort_order, enabled)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7, ?8)",
        params![
            req.item_type,
            req.name,
            req.description,
            req.url,
            req.icon_url.as_deref().unwrap_or(""),
            req.tags.as_deref().unwrap_or(""),
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
    if let Some(ref v) = req.tags {
        updates.push("tags = ?"); param_values.push(Box::new(v.clone()));
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
/// Body: { "current_version": "1.0.0", "version_code": 100, "platform": "windows", "unique_id": "..." }
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
    let result = match db_get_latest(&db, &query.platform) {
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
    };

    // 记录启动数据（不影响版本检查结果）
    if let Some(ref uid) = query.unique_id {
        if !uid.is_empty() {
            let _ = db.execute(
                "INSERT INTO app_launches (unique_id, platform, app_version) VALUES (?1, ?2, ?3)",
                params![uid, query.platform, query.current_version],
            );
        }
    }

    result
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
        service: "zebra-api".to_string(),
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
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, datetime('now'), ?10, ?11)",
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
    let search = query.search.as_deref();

    let db = state.db.lock().unwrap();
    let (items, total) = db_discovery_get_paginated(&db, page, size, sort, item_type, search);

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

/// GET /admin/api/discoveries?page=1&size=20&search=xxx&dtype=0
async fn admin_list_discoveries(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> Json<PaginatedResponse<Vec<DiscoveryItem>>> {
    let page: u32 = query.get("page").and_then(|v| v.parse().ok()).unwrap_or(1).max(1);
    let size: u32 = query.get("size").and_then(|v| v.parse().ok()).unwrap_or(20).min(100);
    let search = query.get("search").map(|s| s.as_str());
    let item_type: Option<i32> = query.get("type").and_then(|v| v.parse().ok());
    let sort = query.get("sort").map(|s| s.as_str()).unwrap_or("time");

    let db = state.db.lock().unwrap();
    let (items, total) = db_discovery_get_paginated_admin(&db, page, size, sort, item_type, search);

    Json(PaginatedResponse {
        success: true,
        data: Some(items),
        total,
        page,
        size,
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

/// GET /admin/api/discoveries/export
async fn admin_export_discoveries(
    State(state): State<Arc<AppState>>,
) -> Response<Body> {
    let db = state.db.lock().unwrap();
    let items = db_discovery_get_all(&db);

    let mut csv = String::from("type,name,description,url,icon_url,tags,sort_order,enabled\n");
    for item in &items {
        csv.push_str(&format!(
            "{},{},{},{},{},{},{},{}\n",
            item.item_type,
            csv_escape(&item.name),
            csv_escape(&item.description),
            csv_escape(&item.url),
            csv_escape(item.icon_url.as_deref().unwrap_or("")),
            csv_escape(item.tags.as_deref().unwrap_or("")),
            item.sort_order,
            item.enabled as i32,
        ));
    }

    (
        StatusCode::OK,
        [
            ("Content-Type", "text/csv; charset=utf-8"),
            ("Content-Disposition", "attachment; filename=\"discoveries.csv\""),
        ],
        csv,
    ).into_response()
}

/// POST /admin/api/discoveries/import (multipart: file=csv)
async fn admin_import_discoveries(
    State(state): State<Arc<AppState>>,
    mut multipart: Multipart,
) -> Result<Json<ApiResponse<serde_json::Value>>, (StatusCode, Json<ApiResponse<()>>)> {
    let mut csv_data = String::new();

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()> { success: false, data: None, error: Some(format!("Failed to read multipart: {}", e)) }),
        )
    })? {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" {
            csv_data = field.text().await.map_err(|e| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<()> { success: false, data: None, error: Some(format!("Failed to read file: {}", e)) }),
                )
            })?;
        }
    }

    if csv_data.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse { success: false, data: None, error: Some("No CSV data".to_string()) }),
        ));
    }

    let db = state.db.lock().unwrap();
    let mut imported = 0u64;
    for (i, line) in csv_data.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() { continue; }
        if i == 0 && line.to_lowercase().contains("type") && line.to_lowercase().contains("name") { continue; }

        let parts = parse_csv_line(line);
        if parts.len() >= 4 {
            let item_type: i32 = parts[0].trim().parse().unwrap_or(0);
            let name = parts[1].trim().to_string();
            let description = parts[2].trim().to_string();
            let url = parts[3].trim().to_string();
            let icon_url = if parts.len() >= 5 { Some(parts[4].trim().to_string()).filter(|s| !s.is_empty()) } else { None };
            let tags = if parts.len() >= 6 { Some(parts[5].trim().to_string()).filter(|s| !s.is_empty()) } else { None };
            let sort_order: i32 = if parts.len() >= 7 { parts[6].trim().parse().unwrap_or(0) } else { 0 };
            let enabled: bool = if parts.len() >= 8 { parts[7].trim() != "0" && parts[7].trim().to_lowercase() != "false" } else { true };

            if !name.is_empty() && !url.is_empty() {
                let req = DiscoveryCreateRequest {
                    item_type,
                    name,
                    description,
                    url,
                    icon_url,
                    tags,
                    sort_order: Some(sort_order),
                    enabled: Some(enabled),
                };
                if db_discovery_create(&db, &req).is_ok() {
                    imported += 1;
                }
            }
        }
    }

    Ok(Json(ApiResponse {
        success: true,
        data: Some(serde_json::json!({ "imported": imported })),
        error: None,
    }))
}

fn csv_escape(field: &str) -> String {
    if field.contains(',') || field.contains('"') || field.contains('\n') {
        format!("\"{}\"", field.replace('"', "\"\""))
    } else {
        field.to_string()
    }
}

fn parse_csv_line(line: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut buffer = String::new();
    let mut in_quotes = false;
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        let c = chars[i];
        if in_quotes {
            if c == '"' {
                if i + 1 < chars.len() && chars[i + 1] == '"' {
                    buffer.push('"');
                    i += 1;
                } else {
                    in_quotes = false;
                }
            } else {
                buffer.push(c);
            }
        } else {
            if c == '"' {
                in_quotes = true;
            } else if c == ',' {
                result.push(buffer.clone());
                buffer.clear();
            } else {
                buffer.push(c);
            }
        }
        i += 1;
    }
    result.push(buffer);
    result
}

// ============================================================
// HTML Admin Panel
// ============================================================
// HTML Admin Panel
// ============================================================

// 编译时嵌入 admin.html 作为后备（确保二进制可独立运行）
const ADMIN_HTML_FALLBACK: &str = include_str!("../static/admin.html");
const BLOG_HTML_FALLBACK: &str = include_str!("../static/blog.html");

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

fn blog_html(static_dir: &str) -> String {
    let html_path = std::path::Path::new(static_dir).join("blog.html");
    if let Ok(content) = std::fs::read_to_string(&html_path) {
        content
    } else {
        BLOG_HTML_FALLBACK.to_string()
    }
}

const POST_HTML_FALLBACK: &str = include_str!("../static/post.html");

fn post_html(static_dir: &str) -> String {
    let html_path = std::path::Path::new(static_dir).join("post.html");
    if let Ok(content) = std::fs::read_to_string(&html_path) {
        content
    } else {
        POST_HTML_FALLBACK.to_string()
    }
}

const STATS_HTML_FALLBACK: &str = include_str!("../static/stats.html");

fn stats_html(static_dir: &str) -> String {
    let html_path = std::path::Path::new(static_dir).join("stats.html");
    if let Ok(content) = std::fs::read_to_string(&html_path) {
        content
    } else {
        STATS_HTML_FALLBACK.to_string()
    }
}

// ============================================================
// Blog 数据库操作
// ============================================================

fn db_blog_get_paginated(
    db: &Connection,
    page: u32,
    size: u32,
    search: Option<&str>,
    published_only: bool,
) -> (Vec<BlogPost>, u64) {
    let offset = (page.saturating_sub(1)) * size;
    let mut conditions: Vec<String> = Vec::new();
    let mut params_list: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if published_only {
        conditions.push("published = 1".to_string());
    }

    if let Some(q) = search {
        if !q.trim().is_empty() {
            let pattern = format!("%{}%", q.trim());
            conditions.push("(title LIKE ? OR summary LIKE ? OR tags LIKE ?)".to_string());
            params_list.push(Box::new(pattern.clone()));
            params_list.push(Box::new(pattern.clone()));
            params_list.push(Box::new(pattern));
        }
    }

    let where_clause = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };

    let count_sql = format!("SELECT COUNT(*) FROM blog_posts {}", where_clause);
    let count_params: Vec<&dyn rusqlite::types::ToSql> = params_list.iter().map(|p| p.as_ref()).collect();
    let total: u64 = db.query_row(&count_sql, count_params.as_slice(), |row| row.get(0)).unwrap_or(0);

    let list_sql = format!(
        "SELECT id, title, content, summary, tags, sort_order, published, created_at, updated_at
         FROM blog_posts {} ORDER BY sort_order DESC, created_at DESC LIMIT ? OFFSET ?",
        where_clause
    );

    params_list.push(Box::new(size as i64));
    params_list.push(Box::new(offset as i64));

    let mut stmt = match db.prepare(&list_sql) {
        Ok(s) => s,
        Err(_) => return (vec![], total),
    };
    let params_ref: Vec<&dyn rusqlite::types::ToSql> = params_list.iter().map(|p| p.as_ref()).collect();
    let rows = stmt.query_map(params_ref.as_slice(), |row| {
        Ok(BlogPost {
            id: row.get(0)?,
            title: row.get(1)?,
            content: row.get(2)?,
            summary: row.get(3)?,
            tags: row.get(4)?,
            sort_order: row.get(5)?,
            published: row.get::<_, i64>(6)? != 0,
            created_at: row.get(7)?,
            updated_at: row.get(8)?,
        })
    }).unwrap();

    let items: Vec<BlogPost> = rows.filter_map(|r| r.ok()).collect();
    (items, total)
}

fn db_blog_get_by_id(db: &Connection, id: i64) -> Option<BlogPost> {
    db.query_row(
        "SELECT id, title, content, summary, tags, sort_order, published, created_at, updated_at
         FROM blog_posts WHERE id = ?1",
        params![id],
        |row| {
            Ok(BlogPost {
                id: row.get(0)?,
                title: row.get(1)?,
                content: row.get(2)?,
                summary: row.get(3)?,
                tags: row.get(4)?,
                sort_order: row.get(5)?,
                published: row.get::<_, i64>(6)? != 0,
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
            })
        },
    ).ok()
}

fn db_blog_create(db: &Connection, req: &BlogCreateRequest) -> Result<BlogPost, String> {
    let published = req.published.unwrap_or(false);
    let sort_order = req.sort_order.unwrap_or(0);
    db.execute(
        "INSERT INTO blog_posts (title, content, summary, tags, sort_order, published)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            req.title,
            req.content,
            req.summary.as_deref().unwrap_or(""),
            req.tags.as_deref().unwrap_or(""),
            sort_order,
            published as i64,
        ],
    ).map_err(|e| e.to_string())?;
    let id = db.last_insert_rowid();
    db_blog_get_by_id(db, id).ok_or_else(|| "Failed to retrieve created blog post".to_string())
}

fn db_blog_update(db: &Connection, id: i64, req: &BlogUpdateRequest) -> Result<BlogPost, String> {
    if db_blog_get_by_id(db, id).is_none() {
        return Err("Blog post not found".to_string());
    }

    let mut updates = Vec::new();
    let mut param_values: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if let Some(ref v) = req.title {
        updates.push("title = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(ref v) = req.content {
        updates.push("content = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(ref v) = req.summary {
        updates.push("summary = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(ref v) = req.tags {
        updates.push("tags = ?"); param_values.push(Box::new(v.clone()));
    }
    if let Some(v) = req.sort_order {
        updates.push("sort_order = ?"); param_values.push(Box::new(v));
    }
    if let Some(v) = req.published {
        updates.push("published = ?"); param_values.push(Box::new(v as i64));
    }

    if updates.is_empty() {
        return db_blog_get_by_id(db, id).ok_or_else(|| "Blog post not found".to_string());
    }

    updates.push("updated_at = datetime('now')");
    let sql = format!("UPDATE blog_posts SET {} WHERE id = ?", updates.join(", "));
    let mut stmt = db.prepare(&sql).map_err(|e| e.to_string())?;
    param_values.push(Box::new(id));
    let params: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|p| p.as_ref()).collect();
    stmt.execute(params.as_slice()).map_err(|e| e.to_string())?;

    db_blog_get_by_id(db, id).ok_or_else(|| "Failed to retrieve updated blog post".to_string())
}

fn db_blog_delete(db: &Connection, id: i64) -> Result<(), String> {
    if db_blog_get_by_id(db, id).is_none() {
        return Err("Blog post not found".to_string());
    }
    db.execute("DELETE FROM blog_posts WHERE id = ?1", params![id]).map_err(|e| e.to_string())?;
    Ok(())
}

fn db_blog_get_all(db: &Connection) -> Vec<BlogPost> {
    let mut stmt = db
        .prepare(
            "SELECT id, title, content, summary, tags, sort_order, published, created_at, updated_at
             FROM blog_posts ORDER BY sort_order DESC, created_at DESC",
        )
        .unwrap();
    let rows = stmt
        .query_map([], |row| {
            Ok(BlogPost {
                id: row.get(0)?,
                title: row.get(1)?,
                content: row.get(2)?,
                summary: row.get(3)?,
                tags: row.get(4)?,
                sort_order: row.get(5)?,
                published: row.get::<_, i64>(6)? != 0,
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
            })
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
}

// ============================================================
// Feedback DB Functions
// ============================================================

fn db_feedback_create(db: &Connection, req: &FeedbackCreateRequest) -> Result<FeedbackItem, String> {
    db.execute(
        "INSERT INTO feedback (email, subject, description, platform, app_version)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![
            req.email,
            req.subject,
            req.description,
            req.platform.as_deref().unwrap_or(""),
            req.app_version.as_deref().unwrap_or(""),
        ],
    ).map_err(|e| e.to_string())?;
    let id = db.last_insert_rowid();
    db_feedback_get_by_id(db, id).ok_or_else(|| "Failed to retrieve created feedback".to_string())
}

fn db_feedback_get_by_id(db: &Connection, id: i64) -> Option<FeedbackItem> {
    db.query_row(
        "SELECT id, email, subject, description, platform, app_version, tags, created_at
         FROM feedback WHERE id = ?1",
        params![id],
        |row| {
            Ok(FeedbackItem {
                id: row.get(0)?,
                email: row.get(1)?,
                subject: row.get(2)?,
                description: row.get(3)?,
                platform: row.get(4)?,
                app_version: row.get(5)?,
                tags: row.get(6)?,
                created_at: row.get(7)?,
            })
        },
    ).ok()
}

fn db_feedback_get_paginated(
    db: &Connection,
    page: u32,
    size: u32,
    search: Option<&str>,
) -> (Vec<FeedbackItem>, u64) {
    let offset = (page.saturating_sub(1)) * size;

    let mut conditions: Vec<String> = Vec::new();
    let mut params_list: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if let Some(q) = search {
        if !q.trim().is_empty() {
            let pattern = format!("%{}%", q.trim());
            conditions.push("(email LIKE ? OR subject LIKE ? OR description LIKE ? OR tags LIKE ?)".to_string());
            params_list.push(Box::new(pattern.clone()));
            params_list.push(Box::new(pattern.clone()));
            params_list.push(Box::new(pattern.clone()));
            params_list.push(Box::new(pattern));
        }
    }

    let where_clause = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };

    let count_sql = format!("SELECT COUNT(*) FROM feedback {}", where_clause);
    let count_params_list: Vec<&dyn rusqlite::types::ToSql> = params_list.iter().map(|p| p.as_ref()).collect();
    let total: u64 = db.query_row(&count_sql, count_params_list.as_slice(), |row| row.get(0)).unwrap_or(0);

    let list_sql = format!(
        "SELECT id, email, subject, description, platform, app_version, tags, created_at
         FROM feedback {} ORDER BY created_at DESC LIMIT ? OFFSET ?",
        where_clause
    );

    params_list.push(Box::new(size as i64));
    params_list.push(Box::new(offset as i64));

    let mut stmt = match db.prepare(&list_sql) {
        Ok(s) => s,
        Err(_) => return (vec![], total),
    };
    let params_ref: Vec<&dyn rusqlite::types::ToSql> = params_list.iter().map(|p| p.as_ref()).collect();
    let rows = stmt.query_map(params_ref.as_slice(), |row| {
        Ok(FeedbackItem {
            id: row.get(0)?,
            email: row.get(1)?,
            subject: row.get(2)?,
            description: row.get(3)?,
            platform: row.get(4)?,
            app_version: row.get(5)?,
            tags: row.get(6)?,
            created_at: row.get(7)?,
        })
    }).unwrap();
    let items: Vec<FeedbackItem> = rows.filter_map(|r| r.ok()).collect();
    (items, total)
}

fn db_feedback_delete(db: &Connection, id: i64) -> Result<(), String> {
    if db_feedback_get_by_id(db, id).is_none() {
        return Err("Feedback not found".to_string());
    }
    db.execute("DELETE FROM feedback WHERE id = ?1", params![id]).map_err(|e| e.to_string())?;
    Ok(())
}

fn db_feedback_batch_delete(db: &Connection, ids: &[i64]) -> Result<u64, String> {
    if ids.is_empty() {
        return Ok(0);
    }
    let placeholders: Vec<String> = ids.iter().enumerate().map(|(i, _)| format!("?{}", i + 1)).collect();
    let sql = format!("DELETE FROM feedback WHERE id IN ({})", placeholders.join(","));
    let mut stmt = db.prepare(&sql).map_err(|e| e.to_string())?;
    let params: Vec<&dyn rusqlite::types::ToSql> = ids.iter().map(|id| id as &dyn rusqlite::types::ToSql).collect();
    let affected = stmt.execute(params.as_slice()).map_err(|e| e.to_string())?;
    Ok(affected as u64)
}

fn db_feedback_update_tags(db: &Connection, id: i64, tags: &str) -> Result<FeedbackItem, String> {
    if db_feedback_get_by_id(db, id).is_none() {
        return Err("Feedback not found".to_string());
    }
    db.execute("UPDATE feedback SET tags = ?1 WHERE id = ?2", params![tags, id]).map_err(|e| e.to_string())?;
    db_feedback_get_by_id(db, id).ok_or_else(|| "Failed to retrieve updated feedback".to_string())
}

// ============================================================
// Blog API Handlers - 公开
// ============================================================

/// GET /api/blog?page=1&size=10&search=xxx
async fn list_published_blog_posts(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<BlogQuery>,
) -> Json<PaginatedResponse<Vec<BlogPost>>> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(10).min(50);
    let search = query.search.as_deref();

    let db = state.db.lock().unwrap();
    let (items, total) = db_blog_get_paginated(&db, page, size, search, true);

    Json(PaginatedResponse {
        success: true,
        data: Some(items),
        total,
        page,
        size,
        error: None,
    })
}

/// GET /api/blog/{id}
async fn get_blog_post(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    match db_blog_get_by_id(&db, id) {
        Some(post) => {
            if !post.published {
                return Err((
                    StatusCode::NOT_FOUND,
                    Json(serde_json::json!({ "success": false, "error": "Blog post not found" })),
                ));
            }
            Ok(Json(serde_json::json!({ "success": true, "data": post })))
        }
        None => Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({ "success": false, "error": "Blog post not found" })),
        )),
    }
}

// ============================================================
// Feedback API Handlers - 公开
// ============================================================

/// POST /api/feedback - 提交反馈（30分钟内同一邮箱只能提交一次）
async fn submit_feedback(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FeedbackCreateRequest>,
) -> Result<Json<ApiResponse<FeedbackItem>>, (StatusCode, Json<ApiResponse<()>>)> {
    if body.email.trim().is_empty() || body.subject.trim().is_empty() || body.description.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Email, subject and description are required".to_string()),
            }),
        ));
    }

    // Rate limiting: 30 minutes per email
    {
        let mut rate_limit = state.feedback_rate_limit.lock().unwrap();
        let email = body.email.trim().to_lowercase();
        if let Some(last_submit) = rate_limit.get(&email) {
            let elapsed = last_submit.elapsed().as_secs();
            if elapsed < 1800 {
                let remaining = 1800 - elapsed;
                let minutes = remaining / 60;
                let seconds = remaining % 60;
                return Err((
                    StatusCode::TOO_MANY_REQUESTS,
                    Json(ApiResponse {
                        success: false,
                        data: None,
                        error: Some(format!(
                            "请等待 {}分{}秒 后再提交",
                            minutes, seconds
                        )),
                    }),
                ));
            }
        }
        rate_limit.insert(email, Instant::now());
    }

    let db = state.db.lock().unwrap();
    match db_feedback_create(&db, &body) {
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

// ============================================================
// Feedback API Handlers - Admin
// ============================================================

/// GET /api/admin/feedback - 反馈列表（分页+搜索）
async fn admin_list_feedback(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<FeedbackQuery>,
) -> Json<PaginatedResponse<Vec<FeedbackItem>>> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(20).min(100);
    let search = query.search.as_deref();

    let db = state.db.lock().unwrap();
    let (items, total) = db_feedback_get_paginated(&db, page, size, search);

    Json(PaginatedResponse {
        success: true,
        data: Some(items),
        total,
        page,
        size,
        error: None,
    })
}

/// GET /api/admin/feedback/:id - 反馈详情
async fn admin_get_feedback(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    match db_feedback_get_by_id(&db, id) {
        Some(item) => Ok(Json(serde_json::json!({ "success": true, "data": item }))),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({ "success": false, "error": "Feedback not found" })),
        )),
    }
}

/// DELETE /api/admin/feedback/:id - 删除单条反馈
async fn admin_delete_feedback(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<ApiResponse<()>>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();
    match db_feedback_delete(&db, id) {
        Ok(()) => Ok(Json(ApiResponse { success: true, data: None, error: None })),
        Err(e) => {
            let status = if e == "Feedback not found" { StatusCode::NOT_FOUND } else { StatusCode::INTERNAL_SERVER_ERROR };
            Err((status, Json(ApiResponse { success: false, data: None, error: Some(e) })))
        }
    }
}

/// POST /api/admin/feedback/batch-delete - 批量删除反馈
async fn admin_batch_delete_feedback(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FeedbackBatchDeleteRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    if body.ids.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "No IDs provided" })),
        ));
    }
    let db = state.db.lock().unwrap();
    match db_feedback_batch_delete(&db, &body.ids) {
        Ok(count) => Ok(Json(serde_json::json!({ "success": true, "data": { "deleted": count } }))),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e })),
        )),
    }
}

/// PUT /api/admin/feedback/:id/tags - 更新标签
async fn admin_update_feedback_tags(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<FeedbackTagRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    match db_feedback_update_tags(&db, id, &body.tags) {
        Ok(item) => Ok(Json(serde_json::json!({ "success": true, "data": item }))),
        Err(e) => {
            let status = if e == "Feedback not found" { StatusCode::NOT_FOUND } else { StatusCode::INTERNAL_SERVER_ERROR };
            Err((status, Json(serde_json::json!({ "success": false, "error": e }))))
        }
    }
}

/// GET /api/admin/feedback/export - 导出反馈为 CSV
async fn admin_export_feedback(
    State(state): State<Arc<AppState>>,
) -> Response<Body> {
    let db = state.db.lock().unwrap();
    let (items, _) = db_feedback_get_paginated(&db, 1, 10000, None);

    let mut csv = String::from("email,subject,description,platform,app_version,tags,created_at\n");
    for item in &items {
        csv.push_str(&format!(
            "{},{},{},{},{},{},{}\n",
            csv_escape(&item.email),
            csv_escape(&item.subject),
            csv_escape(&item.description),
            csv_escape(&item.platform),
            csv_escape(&item.app_version),
            csv_escape(item.tags.as_deref().unwrap_or("")),
            csv_escape(&item.created_at),
        ));
    }

    (
        StatusCode::OK,
        [
            ("Content-Type", "text/csv; charset=utf-8"),
            ("Content-Disposition", "attachment; filename=\"feedback.csv\""),
        ],
        csv,
    ).into_response()
}

/// POST /api/admin/feedback/import - 导入反馈 CSV
async fn admin_import_feedback(
    State(state): State<Arc<AppState>>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let mut csv_data = String::new();

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": format!("Failed to read multipart: {}", e) })),
        )
    })? {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" {
            csv_data = field.text().await.map_err(|e| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(serde_json::json!({ "success": false, "error": format!("Failed to read file: {}", e) })),
                )
            })?;
        }
    }

    if csv_data.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "No CSV data" })),
        ));
    }

    let db = state.db.lock().unwrap();
    let mut imported = 0u64;
    for (i, line) in csv_data.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() { continue; }
        if i == 0 && line.to_lowercase().contains("email") && line.to_lowercase().contains("subject") { continue; }

        let parts = parse_csv_line(line);
        if parts.len() >= 3 {
            let email = parts[0].trim().to_string();
            let subject = parts[1].trim().to_string();
            let description = parts[2].trim().to_string();
            let platform = if parts.len() >= 4 { parts[3].trim().to_string() } else { String::new() };
            let app_version = if parts.len() >= 5 { parts[4].trim().to_string() } else { String::new() };
            let tags = if parts.len() >= 6 { Some(parts[5].trim().to_string()).filter(|s| !s.is_empty()) } else { None };

            if !email.is_empty() && !subject.is_empty() {
                let req = FeedbackCreateRequest {
                    email,
                    subject,
                    description,
                    platform: Some(platform).filter(|s| !s.is_empty()),
                    app_version: Some(app_version).filter(|s| !s.is_empty()),
                };
                if db_feedback_create(&db, &req).is_ok() {
                    // Update tags if provided
                    if let Some(ref t) = tags {
                        if let Some(item) = db_feedback_get_by_id(&db, db.last_insert_rowid()) {
                            let _ = db_feedback_update_tags(&db, item.id, t);
                        }
                    }
                    imported += 1;
                }
            }
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "data": { "imported": imported } })))
}

// ============================================================
// Stats API Handlers
// ============================================================

/// GET /api/admin/stats/data
async fn admin_stats_data(
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db.lock().unwrap();

    let total_users: i64 = db
        .query_row("SELECT COUNT(DISTINCT unique_id) FROM app_launches WHERE unique_id != ''", [], |r| r.get(0))
        .unwrap_or(0);
    let total_launches: i64 = db
        .query_row("SELECT COUNT(*) FROM app_launches", [], |r| r.get(0))
        .unwrap_or(0);

    let today_users: i64 = db
        .query_row("SELECT COUNT(DISTINCT unique_id) FROM app_launches WHERE unique_id != '' AND date(launched_at, 'localtime') = date('now', 'localtime')", [], |r| r.get(0))
        .unwrap_or(0);
    let today_launches: i64 = db
        .query_row("SELECT COUNT(*) FROM app_launches WHERE date(launched_at, 'localtime') = date('now', 'localtime')", [], |r| r.get(0))
        .unwrap_or(0);

    let week_users: i64 = db
        .query_row("SELECT COUNT(DISTINCT unique_id) FROM app_launches WHERE unique_id != '' AND datetime(launched_at, 'localtime') >= datetime('now', 'localtime', '-7 days')", [], |r| r.get(0))
        .unwrap_or(0);
    let week_launches: i64 = db
        .query_row("SELECT COUNT(*) FROM app_launches WHERE datetime(launched_at, 'localtime') >= datetime('now', 'localtime', '-7 days')", [], |r| r.get(0))
        .unwrap_or(0);

    let month_users: i64 = db
        .query_row("SELECT COUNT(DISTINCT unique_id) FROM app_launches WHERE unique_id != '' AND datetime(launched_at, 'localtime') >= datetime('now', 'localtime', '-30 days')", [], |r| r.get(0))
        .unwrap_or(0);
    let month_launches: i64 = db
        .query_row("SELECT COUNT(*) FROM app_launches WHERE datetime(launched_at, 'localtime') >= datetime('now', 'localtime', '-30 days')", [], |r| r.get(0))
        .unwrap_or(0);

    // 按平台统计
    let mut by_platform = Vec::new();
    if let Ok(mut stmt) = db.prepare(
        "SELECT platform, COUNT(DISTINCT unique_id) as users, COUNT(*) as launches
         FROM app_launches WHERE unique_id != ''
         GROUP BY platform ORDER BY launches DESC"
    ) {
        if let Ok(rows) = stmt.query_map([], |row| {
            Ok(serde_json::json!({
                "platform": row.get::<_, String>(0)?,
                "users": row.get::<_, i64>(1)?,
                "launches": row.get::<_, i64>(2)?
            }))
        }) {
            for row in rows.flatten() {
                by_platform.push(row);
            }
        }
    }

    // 按版本统计
    let mut by_version = Vec::new();
    if let Ok(mut stmt) = db.prepare(
        "SELECT app_version, platform, COUNT(DISTINCT unique_id) as users, COUNT(*) as launches
         FROM app_launches WHERE unique_id != ''
         GROUP BY app_version, platform ORDER BY launches DESC LIMIT 20"
    ) {
        if let Ok(rows) = stmt.query_map([], |row| {
            Ok(serde_json::json!({
                "app_version": row.get::<_, String>(0)?,
                "platform": row.get::<_, String>(1)?,
                "users": row.get::<_, i64>(2)?,
                "launches": row.get::<_, i64>(3)?
            }))
        }) {
            for row in rows.flatten() {
                by_version.push(row);
            }
        }
    }

    Ok(Json(serde_json::json!({
        "total_users": total_users,
        "total_launches": total_launches,
        "today_users": today_users,
        "today_launches": today_launches,
        "week_users": week_users,
        "week_launches": week_launches,
        "month_users": month_users,
        "month_launches": month_launches,
        "by_platform": by_platform,
        "by_version": by_version,
    })))
}

/// POST /api/admin/login
async fn admin_login(
    State(state): State<Arc<AppState>>,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let username = body.get("username").and_then(|v| v.as_str()).unwrap_or("");
    let password = body.get("password").and_then(|v| v.as_str()).unwrap_or("");

    if username == state.admin_username && password == state.admin_password {
        let timestamp = Local::now().format("%Y-%m-%dT%H:%M:%S").to_string();
        let token_input = format!("{}:{}:{}", username, password, timestamp);
        let mut hasher = Sha256::new();
        hasher.update(token_input.as_bytes());
        let token = format!("{:x}", hasher.finalize());

        Ok(Json(serde_json::json!({
            "success": true,
            "token": token,
            "expires_in": 86400,
        })))
    } else {
        Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "success": false, "error": "Invalid credentials" })),
        ))
    }
}

/// GET /api/admin/blog?page=1&size=20&search=xxx
async fn admin_list_blog_posts(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<BlogQuery>,
) -> Json<PaginatedResponse<Vec<BlogPost>>> {
    let page = query.page.unwrap_or(1).max(1);
    let size = query.size.unwrap_or(20).min(100);
    let search = query.search.as_deref();

    let db = state.db.lock().unwrap();
    let (items, total) = db_blog_get_paginated(&db, page, size, search, false);

    Json(PaginatedResponse {
        success: true,
        data: Some(items),
        total,
        page,
        size,
        error: None,
    })
}

/// POST /api/admin/blog
async fn admin_create_blog_post(
    State(state): State<Arc<AppState>>,
    Json(body): Json<BlogCreateRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    if body.title.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "Title is required" })),
        ));
    }

    let db = state.db.lock().unwrap();
    match db_blog_create(&db, &body) {
        Ok(post) => Ok(Json(serde_json::json!({ "success": true, "data": post }))),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e })),
        )),
    }
}

/// PUT /api/admin/blog/{id}
async fn admin_update_blog_post(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
    Json(body): Json<BlogUpdateRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    match db_blog_update(&db, id, &body) {
        Ok(post) => Ok(Json(serde_json::json!({ "success": true, "data": post }))),
        Err(e) => {
            let status = if e == "Blog post not found" {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            Err((status, Json(serde_json::json!({ "success": false, "error": e }))))
        }
    }
}

/// DELETE /api/admin/blog/{id}
async fn admin_delete_blog_post(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(id): axum::extract::Path<i64>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    match db_blog_delete(&db, id) {
        Ok(()) => Ok(Json(serde_json::json!({ "success": true }))),
        Err(e) => {
            let status = if e == "Blog post not found" {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            Err((status, Json(serde_json::json!({ "success": false, "error": e }))))
        }
    }
}

/// GET /api/admin/blog/export
async fn admin_export_blog_posts(
    State(state): State<Arc<AppState>>,
) -> Response<Body> {
    let db = state.db.lock().unwrap();
    let items = db_blog_get_all(&db);

    let mut csv = String::from("title,content,summary,tags,sort_order,published\n");
    for item in &items {
        csv.push_str(&format!(
            "{},{},{},{},{},{}\n",
            csv_escape(&item.title),
            csv_escape(&item.content),
            csv_escape(&item.summary),
            csv_escape(item.tags.as_deref().unwrap_or("")),
            item.sort_order,
            item.published as i32,
        ));
    }

    (
        StatusCode::OK,
        [
            ("Content-Type", "text/csv; charset=utf-8"),
            ("Content-Disposition", "attachment; filename=\"blog_posts.csv\""),
        ],
        csv,
    ).into_response()
}

/// POST /api/admin/blog/import (multipart: file=csv)
async fn admin_import_blog_posts(
    State(state): State<Arc<AppState>>,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let mut csv_data = String::new();

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": format!("Failed to read multipart: {}", e) })),
        )
    })? {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" {
            csv_data = field.text().await.map_err(|e| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(serde_json::json!({ "success": false, "error": format!("Failed to read file: {}", e) })),
                )
            })?;
        }
    }

    if csv_data.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "No CSV data" })),
        ));
    }

    let db = state.db.lock().unwrap();
    let mut imported = 0u64;
    for (i, line) in csv_data.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() { continue; }
        if i == 0 && line.to_lowercase().contains("title") && line.to_lowercase().contains("content") { continue; }

        let parts = parse_csv_line(line);
        if parts.len() >= 3 {
            let title = parts[0].trim().to_string();
            let content = parts[1].trim().to_string();
            let summary = if parts.len() >= 3 { parts[2].trim().to_string() } else { String::new() };
            let tags = if parts.len() >= 4 { Some(parts[3].trim().to_string()).filter(|s| !s.is_empty()) } else { None };
            let sort_order: i32 = if parts.len() >= 5 { parts[4].trim().parse().unwrap_or(0) } else { 0 };
            let published: bool = if parts.len() >= 6 { parts[5].trim() != "0" && parts[5].trim().to_lowercase() != "false" } else { false };

            if !title.is_empty() {
                let req = BlogCreateRequest {
                    title,
                    content,
                    summary: Some(summary).filter(|s| !s.is_empty()),
                    tags,
                    sort_order: Some(sort_order),
                    published: Some(published),
                };
                if db_blog_create(&db, &req).is_ok() {
                    imported += 1;
                }
            }
        }
    }

    Ok(Json(serde_json::json!({ "success": true, "data": { "imported": imported } })))
}

// ============================================================
// RSS Feed Generation & Blog/Discovery to RSS
// ============================================================

/// Escape XML special characters
fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
     .replace('<', "&lt;")
     .replace('>', "&gt;")
     .replace('"', "&quot;")
     .replace('\'', "&apos;")
}

/// Generate RSS XML from blog posts
fn generate_blog_rss_xml(posts: &[BlogPost], domain: &str) -> String {
    let mut xml = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    xml.push_str("<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n");
    xml.push_str("<channel>\n");
    xml.push_str(&format!("  <title>Zebra Blog</title>\n"));
    xml.push_str(&format!("  <link>https://{}/api/blog</link>\n", domain));
    xml.push_str("  <description>Zebra 博客文章</description>\n");
    xml.push_str(&format!("  <language>zh-cn</language>\n"));
    xml.push_str(&format!("  <lastBuildDate>{}</lastBuildDate>\n", chrono::Utc::now().format("%a, %d %b %Y %H:%M:%S +0000")));

    for post in posts {
        xml.push_str("  <item>\n");
        xml.push_str(&format!("    <title>{}</title>\n", xml_escape(&post.title)));
        xml.push_str(&format!("    <link>https://{}/api/blog/post/{}</link>\n", domain, post.id));
        xml.push_str(&format!("    <guid>https://{}/api/blog/post/{}</guid>\n", domain, post.id));
        if !post.summary.is_empty() {
            xml.push_str(&format!("    <description>{}</description>\n", xml_escape(&post.summary)));
        } else {
            let desc = if post.content.len() > 200 {
                format!("{}...", &post.content[..200])
            } else {
                post.content.clone()
            };
            xml.push_str(&format!("    <description>{}</description>\n", xml_escape(&desc)));
        }
        if let Some(ref tags) = post.tags {
            for tag in tags.split(',') {
                let tag = tag.trim();
                if !tag.is_empty() {
                    xml.push_str(&format!("    <category>{}</category>\n", xml_escape(tag)));
                }
            }
        }
        xml.push_str(&format!("    <pubDate>{}</pubDate>\n", xml_escape(&post.created_at)));
        xml.push_str("  </item>\n");
    }

    xml.push_str("</channel>\n");
    xml.push_str("</rss>\n");
    xml
}

/// Generate RSS XML from discoveries
fn generate_discovery_rss_xml(items: &[DiscoveryItem], domain: &str) -> String {
    let mut xml = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    xml.push_str("<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n");
    xml.push_str("<channel>\n");
    xml.push_str("  <title>Zebra Discoveries</title>\n");
    xml.push_str(&format!("  <link>https://{}</link>\n", domain));
    xml.push_str("  <description>Zebra 发现推荐</description>\n");
    xml.push_str("  <language>zh-cn</language>\n");
    xml.push_str(&format!("  <lastBuildDate>{}</lastBuildDate>\n", chrono::Utc::now().format("%a, %d %b %Y %H:%M:%S +0000")));

    for item in items {
        xml.push_str("  <item>\n");
        xml.push_str(&format!("    <title>{}</title>\n", xml_escape(&item.name)));
        xml.push_str(&format!("    <link>{}</link>\n", xml_escape(&item.url)));
        xml.push_str(&format!("    <guid>https://{}/discovery/{}</guid>\n", domain, item.id));
        xml.push_str(&format!("    <description>{}</description>\n", xml_escape(&item.description)));
        if let Some(ref tags) = item.tags {
            for tag in tags.split(',') {
                let tag = tag.trim();
                if !tag.is_empty() {
                    xml.push_str(&format!("    <category>{}</category>\n", xml_escape(tag)));
                }
            }
        }
        xml.push_str(&format!("    <pubDate>{}</pubDate>\n", xml_escape(&item.created_at)));
        xml.push_str("  </item>\n");
    }

    xml.push_str("</channel>\n");
    xml.push_str("</rss>\n");
    xml
}

/// GET /api/blog/rss — 博客 RSS Feed
async fn blog_rss_feed(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    let (posts, _) = db_blog_get_paginated(&db, 1, 100, None, true);
    let xml = generate_blog_rss_xml(&posts, &state.domain);
    Ok((
        [(axum::http::header::CONTENT_TYPE, "application/rss+xml; charset=utf-8")],
        xml,
    ))
}

/// GET /api/discoveries/rss — 发现 RSS Feed
async fn discoveries_rss_feed(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    let (items, _) = db_discovery_get_paginated(&db, 1, 100, "time", None, None);
    let xml = generate_discovery_rss_xml(&items, &state.domain);
    Ok((
        [(axum::http::header::CONTENT_TYPE, "application/rss+xml; charset=utf-8")],
        xml,
    ))
}

/// POST /api/admin/rss/generate-from-blog — 将博客添加为 RSS 源
async fn admin_generate_rss_from_blog(
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let rss_url = format!("https://{}/api/blog/rss", state.domain);
    let title = "Zebra Blog".to_string();
    let site_url = format!("https://{}/api/blog", state.domain);

    let db = state.rss_db.db.lock().unwrap();
    let result = db.execute(
        "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, category, enabled, created_at, updated_at)
         VALUES (?1, ?2, ?3, 'rss2', '博客', 1, datetime('now'), datetime('now'))",
        params![title, rss_url, site_url],
    );

    match result {
        Ok(_) => {
            let id = db.last_insert_rowid();
            Ok(Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": id,
                    "title": title,
                    "rss_url": rss_url,
                    "site_url": site_url,
                }
            })))
        }
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e.to_string() })),
        )),
    }
}

/// POST /api/admin/rss/generate-from-discovery — 将发现添加为 RSS 源
async fn admin_generate_rss_from_discovery(
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let rss_url = format!("https://{}/api/discoveries/rss", state.domain);
    let title = "Zebra Discoveries".to_string();
    let site_url = format!("https://{}", state.domain);

    let db = state.rss_db.db.lock().unwrap();
    let result = db.execute(
        "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, category, enabled, created_at, updated_at)
         VALUES (?1, ?2, ?3, 'rss2', '发现', 1, datetime('now'), datetime('now'))",
        params![title, rss_url, site_url],
    );

    match result {
        Ok(_) => {
            let id = db.last_insert_rowid();
            Ok(Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": id,
                    "title": title,
                    "rss_url": rss_url,
                    "site_url": site_url,
                }
            })))
        }
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e.to_string() })),
        )),
    }
}

/// Generate RSS XML from versions
fn generate_versions_rss_xml(versions: &[VersionInfo], domain: &str) -> String {
    let mut xml = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    xml.push_str("<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n");
    xml.push_str("<channel>\n");
    xml.push_str("  <title>Zebra Updates</title>\n");
    xml.push_str(&format!("  <link>https://{}</link>\n", domain));
    xml.push_str("  <description>Zebra 应用版本更新</description>\n");
    xml.push_str("  <language>zh-cn</language>\n");
    xml.push_str(&format!("  <lastBuildDate>{}</lastBuildDate>\n", chrono::Utc::now().format("%a, %d %b %Y %H:%M:%S +0000")));

    for v in versions {
        let download_url = normalize_download_url(&v.download_url, domain);
        xml.push_str("  <item>\n");
        xml.push_str(&format!("    <title>{} {} v{} ({})</title>\n", xml_escape(&v.platform), xml_escape(&v.version_type), xml_escape(&v.version), v.version_code));
        xml.push_str(&format!("    <link>{}</link>\n", xml_escape(&download_url)));
        xml.push_str(&format!("    <guid>https://{}/version/{}/{}</guid>\n", domain, v.platform, v.version_code));
        let desc = if v.changelog.is_empty() {
            format!("New version {} available for {}", v.version, v.platform)
        } else {
            v.changelog.clone()
        };
        xml.push_str(&format!("    <description>{}</description>\n", xml_escape(&desc)));
        xml.push_str(&format!("    <category>{}</category>\n", xml_escape(&v.platform)));
        xml.push_str(&format!("    <pubDate>{}</pubDate>\n", xml_escape(&v.release_date)));
        xml.push_str("  </item>\n");
    }

    xml.push_str("</channel>\n");
    xml.push_str("</rss>\n");
    xml
}

/// GET /api/versions/rss — 版本 RSS Feed
async fn versions_rss_feed(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let db = state.db.lock().unwrap();
    let platforms = ["windows", "linux", "macos", "android", "ios"];
    let mut all_versions = Vec::new();
    for platform in &platforms {
        if let Some(v) = db_get_latest(&db, platform) {
            all_versions.push(v);
        }
    }
    let xml = generate_versions_rss_xml(&all_versions, &state.domain);
    Ok((
        [(axum::http::header::CONTENT_TYPE, "application/rss+xml; charset=utf-8")],
        xml,
    ))
}

/// POST /api/admin/rss/generate-from-versions — 将版本添加为 RSS 源
async fn admin_generate_rss_from_versions(
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let rss_url = format!("https://{}/api/versions/rss", state.domain);
    let title = "Zebra Updates".to_string();
    let site_url = format!("https://{}", state.domain);

    let db = state.rss_db.db.lock().unwrap();
    let result = db.execute(
        "INSERT OR IGNORE INTO rss_sources (title, url, site_url, feed_type, category, enabled, created_at, updated_at)
         VALUES (?1, ?2, ?3, 'rss2', '版本更新', 1, datetime('now'), datetime('now'))",
        params![title, rss_url, site_url],
    );

    match result {
        Ok(_) => {
            let id = db.last_insert_rowid();
            Ok(Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": id,
                    "title": title,
                    "rss_url": rss_url,
                    "site_url": site_url,
                }
            })))
        }
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e.to_string() })),
        )),
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

    // 初始化 RSS 独立数据库
    let rss_db = Arc::new(rss_server::RssDb::open(runtimes_dir));

    let state = Arc::new(AppState {
        db: Mutex::new(conn),
        rss_db: rss_db.clone(),
        uploads_dir: uploads_dir.clone(),
        domain: config.domain().to_string(),
        start_time: Instant::now(),
        started_at: Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        pid: std::process::id(),
        static_dir: static_dir.clone(),
        admin_username: config.admin_username().to_string(),
        admin_password: config.admin_password().to_string(),
        feedback_rate_limit: Mutex::new(std::collections::HashMap::new()),
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
        .route("/api/admin/discoveries/export", get(admin_export_discoveries))
        .route("/api/admin/discoveries/import", post(admin_import_discoveries))
        // 管理后台认证
        .route("/api/admin/login", post(admin_login))
        // 博客管理 API
        .route("/api/admin/blog", get(admin_list_blog_posts))
        .route("/api/admin/blog", post(admin_create_blog_post))
        .route("/api/admin/blog/{id}", axum::routing::put(admin_update_blog_post))
        .route("/api/admin/blog/{id}", axum::routing::delete(admin_delete_blog_post))
        .route("/api/admin/blog/export", get(admin_export_blog_posts))
        .route("/api/admin/blog/import", post(admin_import_blog_posts))
        // 博客公开 API
        .route("/api/blog", get(move |State(s): State<Arc<AppState>>| async move { Html(blog_html(&s.static_dir)) }))
        .route("/api/blog/post/{id}", get(move |State(s): State<Arc<AppState>>| async move { Html(post_html(&s.static_dir)) }))
        .route("/api/blog/posts", get(list_published_blog_posts))
        .route("/api/blog/posts/{id}", get(get_blog_post))
        // 统计 API
        .route("/api/admin/stats", get(move |State(s): State<Arc<AppState>>| async move { Html(stats_html(&s.static_dir)) }))
        .route("/api/admin/stats/data", get(admin_stats_data))
        // 反馈 API
        .route("/api/feedback", post(submit_feedback))
        .route("/api/admin/feedback", get(admin_list_feedback))
        .route("/api/admin/feedback/batch-delete", post(admin_batch_delete_feedback))
        .route("/api/admin/feedback/export", get(admin_export_feedback))
        .route("/api/admin/feedback/import", post(admin_import_feedback))
        .route("/api/admin/feedback/{id}", get(admin_get_feedback))
        .route("/api/admin/feedback/{id}", axum::routing::delete(admin_delete_feedback))
        .route("/api/admin/feedback/{id}/tags", axum::routing::put(admin_update_feedback_tags))
        // RSS Feed Generation API
        .route("/api/blog/rss", get(blog_rss_feed))
        .route("/api/discoveries/rss", get(discoveries_rss_feed))
        .route("/api/versions/rss", get(versions_rss_feed))
        .route("/api/admin/rss/generate-from-blog", post(admin_generate_rss_from_blog))
        .route("/api/admin/rss/generate-from-discovery", post(admin_generate_rss_from_discovery))
        .route("/api/admin/rss/generate-from-versions", post(admin_generate_rss_from_versions))
        // 静态文件服务（上传的文件 + static 目录）
        .nest_service("/api/uploads", ServeDir::new(&uploads_dir))
        .nest_service("/static", ServeDir::new(&static_dir))
        .merge(rss_server::rss_routes().with_state(rss_db))
        .layer(LoggingLayer { log_max_bytes: config.log_max_bytes.unwrap_or(2048) })
        .layer(cors)
        .with_state(state);

    println!("Zebra Update Server running on http://{}", addr);
    println!();
    println!("  Admin Panel:  http://{}/api/admin", addr);
    println!("  User Stats:   http://{}/api/admin/stats", addr);
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
