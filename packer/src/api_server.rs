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

struct AppState {
    db: Mutex<Connection>,
    uploads_dir: String,
    start_time: Instant,
    started_at: String,
    pid: u32,
}

// ============================================================
// 日志系统
// ============================================================

/// 日志文件路径
fn log_file_path() -> PathBuf {
    let log_dir = PathBuf::from("runtimes").join("logs");
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

/// 格式化请求头
fn format_headers(headers: &http::HeaderMap) -> String {
    let mut result = String::new();
    for (key, value) in headers.iter() {
        if let Ok(v) = value.to_str() {
            result.push_str(&format!("    {}: {}\n", key, v));
        }
    }
    result
}

/// 日志中间件 - 记录完整的请求和响应
#[derive(Clone)]
struct LoggingLayer;

impl<S> Layer<S> for LoggingLayer {
    type Service = LoggingService<S>;
    fn layer(&self, inner: S) -> Self::Service {
        LoggingService { inner }
    }
}

#[derive(Clone)]
struct LoggingService<S> {
    inner: S,
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

        // 提取请求信息
        let remote_addr = headers
            .get("x-forwarded-for")
            .or_else(|| headers.get("x-real-ip"))
            .and_then(|v| v.to_str().ok())
            .unwrap_or("-")
            .to_string();

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
            format_headers(&headers)
        );

        let mut inner = self.inner.clone();
        Box::pin(async move {
            // 读取请求体
            let (parts, body) = req.into_parts();
            let body_bytes = body.collect().await.map(|c| c.to_bytes()).unwrap_or_default();
            let body_str = String::from_utf8_lossy(&body_bytes).to_string();

            // 记录请求体
            if !body_str.is_empty() {
                request_log.push_str(&format!("Body:\n{}\n", body_str));
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
                format_headers(&resp_headers)
            );

            if !resp_body_str.is_empty() {
                // 截断过长的响应体
                let display_body = if resp_body_str.len() > 2000 {
                    format!("{}...(truncated, {} bytes total)", &resp_body_str[..2000], resp_body_str.len())
                } else {
                    resp_body_str.clone()
                };
                response_log.push_str(&format!("Body:\n{}\n", display_body));
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

fn db_get_all(db: &Connection) -> Vec<VersionInfo> {
    let mut stmt = db
        .prepare(
            "SELECT id, platform, version, version_code, type, download_url, force_update,
                    changelog, file_size, file_hash, release_date, min_supported_version, file_name
             FROM versions ORDER BY platform, version_code DESC",
        )
        .unwrap();
    let rows = stmt
        .query_map([], |row| {
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
        })
        .unwrap();
    rows.filter_map(|r| r.ok()).collect()
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
                Ok(Json(info))
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
        Some(info) => Ok(Json(info)),
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
) -> Json<ApiResponse<Vec<VersionInfo>>> {
    let db = state.db.lock().unwrap();
    let versions = db_get_all(&db);
    Json(ApiResponse {
        success: true,
        data: Some(versions),
        error: None,
    })
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

    let port: u16 = args.windows(2)
        .find(|w| w[0] == "--port")
        .and_then(|w| w[1].parse().ok())
        .unwrap_or(8686);

    let static_dir = args.windows(2)
        .find(|w| w[0] == "--static-dir")
        .map(|w| w[1].clone())
        .unwrap_or_else(|| "static".to_string());

    // 使用 runtimes 目录存放数据库和上传文件
    let runtimes_dir = "runtimes";
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
        start_time: Instant::now(),
        started_at: Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        pid: std::process::id(),
    });

    let addr = SocketAddr::from(([0, 0, 0, 0], port));

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
        // 管理后台
        .route("/admin", get(move || async move { Html(admin_html(&static_dir_clone)) }))
        .route("/admin/api/versions", get(admin_list_versions))
        .route("/admin/api/upload", post(admin_upload).layer(DefaultBodyLimit::max(100 * 1024 * 1024)))
        .route("/admin/api/versions/{id}", axum::routing::put(admin_update_version))
        .route("/admin/api/versions/{id}", axum::routing::delete(admin_delete_version))
        // 静态文件服务（上传的文件 + static 目录）
        .nest_service("/uploads", ServeDir::new(&uploads_dir))
        .nest_service("/static", ServeDir::new(&static_dir))
        .layer(LoggingLayer)
        .layer(cors)
        .with_state(state);

    println!("Zebra Update Server running on http://{}", addr);
    println!();
    println!("  Admin Panel:  http://{}/admin", addr);
    println!("  API Health:   http://{}/api/health", addr);
    println!("  Version API:  POST http://{}/api/version", addr);
    println!();
    println!("  Data:         runtimes/versions.db");
    println!("  Uploads:      runtimes/uploads/");
    println!("  Logs:         runtimes/logs/api-*.log");
    println!();
    println!("  Options:");
    println!("    --port <PORT>       Server port (default: 8686)");
    println!("    --static-dir <DIR>  Static files directory (default: static)");
    println!();

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
