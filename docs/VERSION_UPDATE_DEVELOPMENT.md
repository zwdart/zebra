# 版本更新系统开发文档

## 架构概览

```
┌─────────────────────────────────────────────────────────┐
│                    Rust API Server                        │
│                (packer/src/api_server.rs)                │
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │  Public API                                   │       │
│  │  GET /api/version?current_version=X&platform=Y│       │
│  │  GET /api/version/latest?platform=Y           │       │
│  │  GET /api/health                              │       │
│  └──────────────────────────────────────────────┘       │
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │  Admin Panel (HTML)                           │       │
│  │  GET /admin              → 管理后台页面        │       │
│  │  GET /admin/api/versions → 版本列表           │       │
│  │  POST /admin/api/upload  → 上传文件/添加URL   │       │
│  │  PUT /admin/api/versions/:id → 编辑版本信息    │       │
│  │  DELETE /admin/api/versions/:id → 删除版本     │       │
│  └──────────────────────────────────────────────┘       │
│                                                          │
│  数据存储: SQLite (data/versions.db)                     │
│  文件存储: data/uploads/                                 │
└──────────────────────┬──────────────────────────────────┘
                       │ HTTP
┌──────────────────────▼──────────────────────────────────┐
│                  Flutter Client                           │
│                                                          │
│  UpdateService  ──→  HTTP 请求 + 文件下载/URL跳转        │
│  UpdateProvider ──→  状态管理 (Provider)                   │
│  UpdateDialog   ──→  UI 展示                              │
└─────────────────────────────────────────────────────────┘
```

## Rust API Server

### 文件结构

```
packer/
├── Cargo.toml
└── src/
    └── api_server.rs    # 单文件完整实现
```

运行时生成：
```
data/
├── versions.db          # SQLite 数据库
└── uploads/             # 上传的安装包文件
```

### 依赖

```toml
axum = "0.8"           # HTTP 框架
tokio = "1"            # 异步运行时
rusqlite = "0.32"      # SQLite（bundled）
sha2 = "0.10"          # SHA-256 哈希
tower-http = "0.6"     # CORS + 静态文件服务
chrono = "0.4"         # 时间处理
```

### 构建和运行

```bash
cd packer

# 编译
cargo build --release --bin zebra-api --features api-server

# 运行（默认端口 8686，数据目录 ./data）
./target/release/zebra-api

# 指定端口和数据目录
./target/release/zebra-api --port 9090 --data-dir /var/lib/zebra-api
```

### 数据库表结构

```sql
CREATE TABLE versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    platform TEXT NOT NULL,           -- windows/linux/macos/android/ios
    version TEXT NOT NULL,            -- 版本号 如 1.2.0
    version_code INTEGER NOT NULL,    -- 版本码 用于比较（手动设置或使用自增ID）
    type TEXT NOT NULL DEFAULT 'file', -- 类型: file(文件) 或 url(外部链接)
    download_url TEXT NOT NULL,       -- 下载路径 /uploads/xxx.exe 或外部URL
    force_update INTEGER NOT NULL,    -- 是否强制更新 0/1
    changelog TEXT NOT NULL,          -- 更新日志
    file_size INTEGER NOT NULL,       -- 文件大小（字节）
    file_hash TEXT NOT NULL,          -- SHA-256 哈希
    release_date TEXT NOT NULL,       -- 发布日期时间
    min_supported_version TEXT,       -- 最低支持版本
    file_name TEXT NOT NULL,          -- 原始文件名
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

### API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/version?current_version=1.0.0&platform=windows` | 检查更新（客户端调用） |
| GET | `/api/version/latest?platform=windows` | 获取最新版本信息 |
| GET | `/api/health` | 健康检查（含运行时间、PID） |
| GET | `/admin` | 管理后台页面 |
| GET | `/admin/api/versions` | 获取所有版本 |
| POST | `/admin/api/upload` | 上传文件或添加URL创建版本 |
| PUT | `/admin/api/versions/:id` | 编辑版本信息 |
| DELETE | `/admin/api/versions/:id` | 删除版本 |

### 上传接口 (POST /admin/api/upload)

Content-Type: `multipart/form-data`

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| type | String | 否 | "file" 或 "url"，默认 "file" |
| file | File | file类型必填 | 应用安装包文件 |
| external_url | String | url类型必填 | 外部下载链接 |
| platform | String | 是 | 平台：windows/linux/macos/android/ios |
| version | String | 否 | 版本号，留空从文件名自动识别 |
| version_code | String | 否 | 版本码，留空使用数据库自增ID |
| changelog | String | 否 | 更新日志 |
| force_update | String | 否 | "true" 或 "false" |
| min_supported_version | String | 否 | 最低支持版本 |

**版本类型说明：**
- `file`：上传文件，客户端下载并安装
- `url`：外部链接，客户端跳转浏览器打开

**自动识别功能：**
- 版本号：从文件名自动提取，如 `zebra-ssh-1.2.0.exe` → `1.2.0`
- 文件大小：自动计算（仅 file 类型）
- 文件哈希：自动计算 SHA-256（仅 file 类型）
- 发布日期：自动设为当前时间

### 健康检查接口 (GET /api/health)

响应示例：
```json
{
  "status": "ok",
  "service": "zebra-update-api",
  "version": "1.0.0",
  "uptime_secs": 3600,
  "started_at": "2026-07-13 10:00:00",
  "pid": 12345
}
```

---

## Flutter Client

### 文件结构

```
lib/
├── services/
│   └── update_service.dart      # 网络请求 + 文件下载/URL跳转
├── providers/
│   └── update_provider.dart     # 状态管理
├── screens/
│   ├── update_dialog.dart       # 更新弹窗 UI
│   ├── home_screen.dart         # 启动时静默检查
│   └── settings_screen.dart     # 手动检查入口
└── main.dart                    # 注册 UpdateProvider
```

### 核心 API 调用

```dart
// 检查更新
GET /api/version?current_version=1.0.0&platform=windows

// 响应（有更新 - 文件类型）
{
  "id": 1,
  "platform": "windows",
  "version": "1.1.0",
  "version_code": 10100,
  "type": "file",
  "download_url": "/uploads/zebra-ssh-1.1.0.exe",
  "force_update": false,
  "changelog": "- 新功能\n- 修复",
  "file_size": 15000000,
  "file_hash": "sha256:abc...",
  "release_date": "2026-07-13 10:00:00",
  "min_supported_version": "1.0.0",
  "file_name": "zebra-ssh-1.1.0.exe"
}

// 响应（有更新 - URL类型）
{
  "id": 2,
  "platform": "windows",
  "version": "1.2.0",
  "version_code": 10200,
  "type": "url",
  "download_url": "https://example.com/download",
  "force_update": false,
  "changelog": "跳转浏览器下载",
  "file_size": 0,
  "file_hash": "",
  "release_date": "2026-07-13 12:00:00",
  "min_supported_version": null,
  "file_name": ""
}

// 响应（无更新）
{
  "id": 0,
  "version": "1.0.0",
  "version_code": 0,
  "download_url": "",
  ...
}
```

### 版本类型处理

```dart
// 客户端根据 type 字段处理更新
if (updateInfo.isUrlType) {
  // URL 类型：跳转浏览器
  await UpdateService.openExternalUrl(updateInfo.downloadUrl);
} else {
  // 文件类型：下载并安装
  // ... 下载逻辑
}
```

### 平台行为差异

| 平台 | 文件类型 | URL类型 |
|------|----------|---------|
| Windows | 下载 .exe → 运行安装 | 跳转浏览器 |
| Linux | 下载可执行文件 → chmod +x | 跳转浏览器 |
| macOS | 下载 .dmg → open | 跳转浏览器 |
| Android | 下载 .apk 或跳转商店 | 跳转浏览器 |
| iOS | 跳转 App Store | 跳转浏览器 |

---

## 管理后台使用

### 访问

浏览器打开 `http://服务器IP:8686/admin`

### 上传新版本（文件类型）

1. 点击「+ 上传新版本」
2. 类型选择「上传文件」
3. 拖拽或选择安装包文件
4. 选择平台
5. 版本号可留空（自动从文件名识别）
6. 版本码可留空（自动使用数据库ID）
7. 填写更新日志（可选）
8. 点击「上传」

### 添加版本（URL类型）

1. 点击「+ 上传新版本」
2. 类型选择「外部链接」
3. 输入下载链接
4. 选择平台
5. 输入版本号
6. 版本码可留空（自动使用数据库ID）
7. 填写更新日志（可选）
8. 点击「上传」

### 编辑版本

点击版本列表中的「编辑」按钮，可修改：
- 版本号
- 版本码
- 更新日志
- 最低支持版本
- 强制更新设置

### 删除版本

点击「删除」按钮，确认后删除版本记录和文件。

### 版本列表说明

| 列 | 说明 |
|---|------|
| 版本码 | 用于版本比较，越大越新 |
| 类型 | 文件（上传安装包）或 链接（外部URL） |
| 最新 | 同平台版本码最大的记录显示 [最新] 标识 |

---

## 部署

### 编译

```bash
cd packer
cargo build --release --bin zebra-api --features api-server
```

### 部署到服务器

```bash
# 上传二进制文件
scp target/release/zebra-api user@server:/opt/zebra-api/

# SSH 到服务器
ssh user@server

# 创建数据目录
mkdir -p /opt/zebra-api/data

# 运行
cd /opt/zebra-api
./zebra-api --port 8686 --data-dir ./data
```

### 后台运行（systemd）

```ini
# /etc/systemd/system/zebra-api.service
[Unit]
Description=Zebra Update API Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/zebra-api
ExecStart=/opt/zebra-api/zebra-api --port 8686 --data-dir ./data
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable zebra-api
sudo systemctl start zebra-api
```

### Nginx 反向代理

```nginx
server {
    listen 80;
    server_name api.zebra.dart.xin;

    location / {
        proxy_pass http://127.0.0.1:8686;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # 文件上传大小限制
    client_max_body_size 100M;
}
```
