# Zebra API Server (zebra-api)

Rust 后端服务，提供版本管理、发现数据、博客、反馈等功能的 REST API。

## 技术栈

- **语言**: Rust 2021 Edition
- **Web 框架**: Axum 0.8
- **数据库**: SQLite (rusqlite)
- **异步运行时**: Tokio
- **日志**: 自定义文件日志 + stderr

## 架构

```
packer/
├── src/
│   ├── api_server.rs    # API 服务主文件 (所有路由+业务逻辑)
│   ├── main.rs          # 打包工具入口
│   ├── bin_pack.rs      # 打包二进制
│   ├── bin_reader.rs    # 读取二进制
│   └── icon_gen.rs      # 图标生成
├── static/              # 管理后台 HTML 静态文件
├── runtimes/            # 数据目录 (数据库+上传文件+日志)
├── config.toml          # 配置文件
├── Cargo.toml           # 依赖配置
└── Makefile             # 构建脚本
```

## 配置

`config.toml`:

```toml
port = 8686                          # 监听端口
domain = "zebra.dart.xin"            # 下载 URL 域名
data_dir = "runtimes"                # 数据目录
static_dir = "static"                # 静态文件目录
log_max_bytes = 2048                 # 日志截断字节数
admin_username = "admin"             # 管理员用户名
admin_password = "zebra2024"         # 管理员密码
```

命令行参数优先级高于 config.toml:

```bash
zebra-api --port 8080 --static-dir ./static
```

## 数据库表结构

### versions - 版本发布记录

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| platform | TEXT | - | 平台: windows/linux/macos/android/ios |
| version | TEXT | - | 版本号 (语义化, 如 "1.2.0") |
| version_code | INTEGER | 0 | 整数版本号 (用于精确比较) |
| type | TEXT | 'file' | 类型: file=文件上传, url=外部链接 |
| download_url | TEXT | '' | 下载地址 (相对路径或完整 URL) |
| force_update | INTEGER | 0 | 是否强制更新 (0=否, 1=是) |
| changelog | TEXT | '' | 更新日志 |
| file_size | INTEGER | 0 | 文件大小 (字节) |
| file_hash | TEXT | '' | SHA256 哈希 (格式: sha256:hex) |
| release_date | TEXT | '' | 发布日期 (YYYY-MM-DD) |
| min_supported_version | TEXT | NULL | 最低支持版本 (低于此版本强制更新) |
| file_name | TEXT | '' | 原始文件名 |
| created_at | TEXT | datetime('now') | 创建时间 |
| updated_at | TEXT | datetime('now') | 更新时间 |

索引: `idx_versions_platform`, `idx_versions_platform_version`

### discoveries - 发现/推荐内容

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| type | INTEGER | 0 | 类型: 0=官方, 1=推荐, 2=广告 |
| name | TEXT | '' | 名称 |
| description | TEXT | '' | 描述 |
| url | TEXT | '' | 链接地址 |
| icon_url | TEXT | '' | 图标 URL |
| tags | TEXT | '' | 标签 (逗号分隔) |
| clicks | INTEGER | 0 | 点击次数 |
| sort_order | INTEGER | 0 | 排序权重 (越小越靠前) |
| enabled | INTEGER | 1 | 是否启用 (0=禁用, 1=启用) |
| created_at | TEXT | datetime('now') | 创建时间 |
| updated_at | TEXT | datetime('now') | 更新时间 |

索引: `idx_discoveries_type`, `idx_discoveries_enabled`, `idx_discoveries_sort_order`

### blog_posts - 博客文章

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| title | TEXT | '' | 标题 |
| content | TEXT | '' | 内容 (Markdown) |
| summary | TEXT | '' | 摘要 |
| tags | TEXT | '' | 标签 (逗号分隔) |
| sort_order | INTEGER | 0 | 排序权重 |
| published | INTEGER | 0 | 是否发布 (0=草稿, 1=已发布) |
| created_at | TEXT | datetime('now') | 创建时间 |
| updated_at | TEXT | datetime('now') | 更新时间 |

索引: `idx_blog_posts_published`, `idx_blog_posts_created`, `idx_blog_posts_sort`

### feedback - 用户反馈

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| email | TEXT | '' | 用户邮箱 |
| subject | TEXT | '' | 主题 |
| description | TEXT | '' | 详细描述 |
| platform | TEXT | '' | 平台 (客户端自动上报) |
| app_version | TEXT | '' | 应用版本 (客户端自动上报) |
| tags | TEXT | '' | 管理员标签 |
| created_at | TEXT | datetime('now') | 提交时间 |

索引: `idx_feedback_created_at`

### app_launches - 启动统计

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| unique_id | TEXT | '' | 设备唯一标识 |
| platform | TEXT | '' | 平台 |
| app_version | TEXT | '' | 应用版本 |
| launched_at | TEXT | datetime('now') | 启动时间 |

索引: `idx_app_launches_unique_id`, `idx_app_launches_launched_at`

## API 接口总览

### 公开 API

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/version` | 检查更新 |
| GET | `/api/version/latest` | 获取最新版本 |
| GET | `/api/health` | 健康检查 |
| GET | `/api/discoveries` | 发现列表 (分页) |
| GET | `/api/discoveries/random` | 随机发现 |
| POST | `/api/discoveries/{id}/click` | 记录点击 |
| GET | `/api/blog/posts` | 已发布博客列表 |
| GET | `/api/blog/posts/{id}` | 博客详情 |
| POST | `/api/feedback` | 提交反馈 |

### 管理 API

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/admin/login` | 管理员登录 |
| GET | `/api/admin/versions` | 版本列表 |
| POST | `/api/admin/upload` | 上传版本文件 |
| PUT | `/api/admin/versions/{id}` | 更新版本 |
| DELETE | `/api/admin/versions/{id}` | 删除版本 |
| GET | `/api/admin/discoveries` | 发现管理列表 |
| POST | `/api/admin/discoveries` | 创建发现 |
| PUT | `/api/admin/discoveries/{id}` | 更新发现 |
| DELETE | `/api/admin/discoveries/{id}` | 删除发现 |
| GET | `/api/admin/discoveries/export` | 导出 CSV |
| POST | `/api/admin/discoveries/import` | 导入 CSV |
| GET | `/api/admin/blog` | 博客管理列表 |
| POST | `/api/admin/blog` | 创建博客 |
| PUT | `/api/admin/blog/{id}` | 更新博客 |
| DELETE | `/api/admin/blog/{id}` | 删除博客 |
| GET | `/api/admin/blog/export` | 导出 CSV |
| POST | `/api/admin/blog/import` | 导入 CSV |
| GET | `/api/admin/feedback` | 反馈列表 |
| GET | `/api/admin/feedback/{id}` | 反馈详情 |
| DELETE | `/api/admin/feedback/{id}` | 删除反馈 |
| POST | `/api/admin/feedback/batch-delete` | 批量删除 |
| PUT | `/api/admin/feedback/{id}/tags` | 更新标签 |
| GET | `/api/admin/stats/data` | 统计数据 |

### 静态页面

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/admin` | 管理后台页面 (HTML) |
| GET | `/api/admin/stats` | 统计页面 (HTML) |
| GET | `/api/blog` | 博客列表页面 (HTML) |
| GET | `/api/blog/post/{id}` | 博客文章页面 (HTML) |
| GET | `/api/uploads/{file}` | 上传文件下载 |
| GET | `/static/{file}` | 静态资源 |

## 接口详细参数

### POST /api/version - 检查更新

**请求体 (JSON)**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| current_version | string | 是 | 当前客户端版本号 |
| version_code | integer | 否 | 当前整数版本号 (优先用于比较) |
| platform | string | 是 | 平台: windows/linux/macos/android/ios |
| unique_id | string | 否 | 设备唯一标识 (用于统计) |

**响应 (200, 有更新)**:

返回 `VersionInfo` 对象 (见下方数据结构)。

**响应 (200, 已是最新)**:

返回 `VersionInfo` 对象，`id=0`, `version` 为客户端当前版本，其余字段为空。

**错误**: 400 (platform 无效), 404 (无该平台版本)

---

### GET /api/version/latest - 获取最新版本

**查询参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| platform | string | 否 | 平台，默认 "windows" |

**响应 (200)**: 返回 `VersionInfo` 对象。

**错误**: 404 (无该平台版本)

---

### GET /api/health - 健康检查

**响应 (200)**:

```json
{
  "status": "ok",
  "service": "zebra-api",
  "version": "1.0.0",
  "uptime_secs": 3600,
  "started_at": "2024-01-01 10:00:00",
  "pid": 12345
}
```

---

### GET /api/discoveries - 发现列表

**查询参数**:

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| page | integer | 否 | 1 | 页码 (最小 1) |
| size | integer | 否 | 10 | 每页数量 (最大 50) |
| sort | string | 否 | "time" | 排序: time=按时间, hot=按点击量 |
| type | integer | 否 | - | 筛选类型: 0=官方, 1=推荐, 2=广告 |
| search | string | 否 | - | 搜索关键词 (模糊匹配 name/description/tags) |

**响应 (200)**:

```json
{
  "success": true,
  "data": [ { "id": 1, "type": 0, "name": "...", ... } ],
  "total": 100,
  "page": 1,
  "size": 10,
  "error": null
}
```

仅返回 `enabled=1` 的记录。

---

### GET /api/discoveries/random - 随机发现

**响应 (200)**: 返回单个 `DiscoveryItem`。

**错误**: 404 (无可用发现)

---

### POST /api/discoveries/{id}/click - 记录点击

**路径参数**: `id` - 发现项 ID

**响应 (200)**: 返回更新后的 `DiscoveryItem` (clicks +1)。

**错误**: 404 (不存在)

---

### GET /api/blog/posts - 已发布博客

**查询参数**:

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| page | integer | 否 | 1 | 页码 |
| size | integer | 否 | 10 | 每页数量 (最大 50) |
| search | string | 否 | - | 搜索 (模糊匹配 title/summary/tags) |

**响应 (200)**: 分页返回 `BlogPost` 数组，仅 `published=1`。

---

### GET /api/blog/posts/{id} - 博客详情

**路径参数**: `id` - 博客 ID

**响应 (200)**:

```json
{ "success": true, "data": { "id": 1, "title": "...", "content": "...", ... } }
```

**错误**: 404 (不存在或未发布)

---

### POST /api/feedback - 提交反馈

**请求体 (JSON)**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| email | string | 是 | 联系邮箱 |
| subject | string | 是 | 反馈主题 |
| description | string | 是 | 详细描述 |
| platform | string | 否 | 平台 (客户端自动填充) |
| app_version | string | 否 | 应用版本 (客户端自动填充) |

**限流**: 同一邮箱 30 分钟内只能提交一次。

**响应 (200)**: 返回创建的 `FeedbackItem`。

**错误**: 400 (必填字段为空), 429 (限流)

---

### POST /api/admin/login - 管理员登录

**请求体 (JSON)**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| username | string | 是 | 用户名 (默认: admin) |
| password | string | 是 | 密码 (默认: zebra2024) |

**响应 (200)**:

```json
{ "success": true, "token": "sha256hash...", "expires_in": 86400 }
```

**错误**: 401 (凭证错误)

---

### POST /api/admin/upload - 上传版本文件

**请求**: `multipart/form-data`

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| file | file | 是* | 版本文件 (type=file 时必填) |
| platform | string | 是 | 平台 |
| version | string | 否 | 版本号 (可从文件名推断) |
| version_code | string | 否 | 整数版本号 (不填则用数据库自增 ID) |
| type | string | 否 | 类型: file(默认) 或 url |
| external_url | string | 是* | 外部链接 (type=url 时必填) |
| changelog | string | 否 | 更新日志 |
| force_update | string | 否 | "true" 表示强制更新 |
| min_supported_version | string | 否 | 最低支持版本 |

**响应 (200)**: 返回创建的 `VersionInfo`。

---

### PUT /api/admin/versions/{id} - 更新版本

**路径参数**: `id` - 版本 ID

**请求体 (JSON)**: 所有字段可选，仅更新提供的字段。

| 字段 | 类型 | 说明 |
|------|------|------|
| version | string | 版本号 |
| version_code | integer | 整数版本号 |
| changelog | string | 更新日志 |
| force_update | boolean | 强制更新 |
| min_supported_version | string | 最低支持版本 |
| file_name | string | 文件名 |
| download_url | string | 下载地址 |

**响应 (200)**: 返回更新后的 `VersionInfo`。

**错误**: 404 (不存在)

---

### DELETE /api/admin/versions/{id} - 删除版本

**路径参数**: `id` - 版本 ID

同时删除关联的上传文件。

**响应 (200)**: `{ "success": true, "data": null, "error": null }`

**错误**: 404 (不存在)

---

### POST /api/admin/discoveries - 创建发现

**请求体 (JSON)**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| type | integer | 是 | 0=官方, 1=推荐, 2=广告 |
| name | string | 是 | 名称 |
| description | string | 是 | 描述 |
| url | string | 是 | 链接 |
| icon_url | string | 否 | 图标 URL |
| tags | string | 否 | 标签 |
| sort_order | integer | 否 | 排序 (默认 0) |
| enabled | boolean | 否 | 启用状态 (默认 true) |

**响应 (200)**: 返回创建的 `DiscoveryItem`。

**错误**: 400 (name/url 为空, type 无效)

---

### PUT /api/admin/discoveries/{id} - 更新发现

**路径参数**: `id` - 发现 ID

**请求体 (JSON)**: 所有字段可选。

| 字段 | 类型 | 说明 |
|------|------|------|
| type | integer | 类型 |
| name | string | 名称 |
| description | string | 描述 |
| url | string | 链接 |
| icon_url | string | 图标 |
| tags | string | 标签 |
| clicks | integer | 点击数 |
| sort_order | integer | 排序 |
| enabled | boolean | 启用状态 |

**响应 (200)**: 返回更新后的 `DiscoveryItem`。

**错误**: 404 (不存在)

---

### DELETE /api/admin/discoveries/{id} - 删除发现

**响应 (200)**: 成功。**错误**: 404 (不存在)

---

### GET /api/admin/discoveries/export - 导出 CSV

**响应**: CSV 文件下载，字段: type,name,description,url,icon_url,tags,sort_order,enabled

---

### POST /api/admin/discoveries/import - 导入 CSV

**请求**: `multipart/form-data`，字段 `file` 为 CSV 文件。

**响应 (200)**: `{ "success": true, "data": { "imported": 5 }, "error": null }`

---

### GET /api/admin/blog - 博客管理列表

**查询参数**:

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| page | integer | 否 | 1 | 页码 |
| size | integer | 否 | 20 | 每页数量 (最大 100) |
| search | string | 否 | - | 搜索 (模糊匹配 title/summary/tags) |

返回所有记录 (包括未发布的草稿)。

---

### GET /api/admin/blog/export - 导出博客 CSV

**响应**: CSV 文件下载，字段: title,content,summary,tags,sort_order,published

---

### POST /api/admin/blog/import - 导入博客 CSV

**请求**: `multipart/form-data`，字段 `file` 为 CSV 文件。

**响应 (200)**: `{ "success": true, "data": { "imported": 5 } }`

---

### POST /api/admin/blog - 创建博客

**请求体 (JSON)**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| title | string | 是 | 标题 |
| content | string | 是 | 内容 (Markdown) |
| summary | string | 否 | 摘要 |
| tags | string | 否 | 标签 |
| sort_order | integer | 否 | 排序 (默认 0) |
| published | boolean | 否 | 是否发布 (默认 false) |

**响应 (200)**: 返回创建的 `BlogPost`。

**错误**: 400 (title 为空)

---

### PUT /api/admin/blog/{id} - 更新博客

**请求体 (JSON)**: 所有字段可选。

| 字段 | 类型 | 说明 |
|------|------|------|
| title | string | 标题 |
| content | string | 内容 |
| summary | string | 摘要 |
| tags | string | 标签 |
| sort_order | integer | 排序 |
| published | boolean | 发布状态 |

**响应 (200)**: 返回更新后的 `BlogPost`。

**错误**: 404 (不存在)

---

### DELETE /api/admin/blog/{id} - 删除博客

**响应 (200)**: 成功。**错误**: 404 (不存在)

---

### GET /api/admin/feedback - 反馈列表

**查询参数**:

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| page | integer | 否 | 1 | 页码 |
| size | integer | 否 | 20 | 每页数量 (最大 100) |
| search | string | 否 | - | 搜索 (模糊匹配 email/subject/description/tags) |

---

### POST /api/admin/feedback/batch-delete - 批量删除

**请求体 (JSON)**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| ids | integer[] | 是 | 要删除的反馈 ID 数组 |

**响应 (200)**: `{ "success": true, "data": { "deleted": 3 } }`

**错误**: 400 (ids 为空)

---

### PUT /api/admin/feedback/{id}/tags - 更新标签

**路径参数**: `id` - 反馈 ID

**请求体 (JSON)**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| tags | string | 是 | 标签内容 |

**响应 (200)**: 返回更新后的 `FeedbackItem`。

**错误**: 404 (不存在)

---

### GET /api/admin/feedback/{id} - 反馈详情

**路径参数**: `id` - 反馈 ID

**响应 (200)**:

```json
{ "success": true, "data": { "id": 1, "email": "...", ... } }
```

**错误**: 404 (不存在)

---

### DELETE /api/admin/feedback/{id} - 删除单条反馈

**路径参数**: `id` - 反馈 ID

**响应 (200)**: `{ "success": true, "data": null, "error": null }`

**错误**: 404 (不存在)

---

### GET /api/admin/stats/data - 统计数据

**响应 (200)**:

```json
{
  "total_users": 100,
  "total_launches": 500,
  "today_users": 10,
  "today_launches": 30,
  "week_users": 50,
  "week_launches": 200,
  "month_users": 80,
  "month_launches": 400,
  "by_platform": [
    { "platform": "windows", "users": 60, "launches": 300 },
    { "platform": "android", "users": 30, "launches": 150 }
  ],
  "by_version": [
    { "app_version": "1.2.0", "platform": "windows", "users": 40, "launches": 200 }
  ]
}
```

---

## 通用数据结构

### VersionInfo

```json
{
  "id": 1,                          // 记录 ID
  "platform": "windows",            // 平台
  "version": "1.2.0",               // 版本号
  "version_code": 120,              // 整数版本号
  "type": "file",                   // file 或 url
  "download_url": "https://...",    // 下载地址
  "force_update": false,            // 是否强制更新
  "changelog": "更新内容",           // 更新日志
  "file_size": 10485760,            // 文件大小 (字节)
  "file_hash": "sha256:abc...",     // SHA256 哈希
  "release_date": "2024-01-01",     // 发布日期
  "min_supported_version": "1.0.0", // 最低支持版本 (可为 null)
  "file_name": "zebra-1.2.0.exe"    // 原始文件名
}
```

### DiscoveryItem

```json
{
  "id": 1,
  "type": 0,                        // 0=官方, 1=推荐, 2=广告
  "name": "工具名称",
  "description": "工具描述",
  "url": "https://...",
  "icon_url": "https://...",        // 可为 null
  "tags": "标签1,标签2",            // 可为 null
  "clicks": 100,
  "sort_order": 0,
  "enabled": true,
  "created_at": "2024-01-01 10:00:00",
  "updated_at": "2024-01-01 10:00:00"
}
```

### BlogPost

```json
{
  "id": 1,
  "title": "文章标题",
  "content": "Markdown 内容...",
  "summary": "摘要",
  "tags": "flutter,dart",           // 可为 null
  "sort_order": 0,
  "published": true,
  "created_at": "2024-01-01 10:00:00",
  "updated_at": "2024-01-01 10:00:00"
}
```

### FeedbackItem

```json
{
  "id": 1,
  "email": "user@example.com",
  "subject": "反馈主题",
  "description": "详细描述",
  "platform": "windows",
  "app_version": "1.2.0",
  "tags": "已处理",                 // 可为 null
  "created_at": "2024-01-01 10:00:00"
}
```

## 错误码

### HTTP 状态码

| 状态码 | 含义 | 场景 |
|--------|------|------|
| 200 | OK | 请求成功 |
| 400 | Bad Request | 参数校验失败 |
| 401 | Unauthorized | 管理员认证失败 |
| 404 | Not Found | 资源不存在 |
| 429 | Too Many Requests | 反馈提交限流 |
| 500 | Internal Server Error | 服务端内部错误 |

### 业务错误响应格式

所有错误响应统一格式:

```json
{
  "success": false,
  "data": null,
  "error": "错误描述信息"
}
```

分页接口错误格式:

```json
{
  "success": false,
  "data": null,
  "total": 0,
  "page": 1,
  "size": 10,
  "error": "错误描述信息"
}
```

### 错误详情

| 接口 | 错误信息 | 原因 |
|------|----------|------|
| POST /api/version | `Invalid platform: xxx` | platform 不在 windows/linux/macos/android/ios 中 |
| POST /api/version | `No version found for platform: xxx` | 该平台无版本记录 |
| POST /api/admin/login | `Invalid credentials` | 用户名或密码错误 |
| POST /api/admin/upload | `No file uploaded` | file 类型未上传文件 |
| POST /api/admin/upload | `URL type requires external_url` | url 类型未提供 external_url |
| POST /api/admin/upload | `Version is required` | 未提供版本号且文件名无法推断 |
| PUT /api/admin/versions/{id} | `Version not found` | 版本 ID 不存在 |
| DELETE /api/admin/versions/{id} | `Version not found` | 版本 ID 不存在 |
| POST /api/feedback | `请等待 X分X秒 后再提交` | 同一邮箱 30 分钟内重复提交 |
| POST /api/feedback | `Email, subject and description are required` | 必填字段为空 |
| POST /api/admin/discoveries | `Name and URL are required` | name 或 url 为空 |
| POST /api/admin/discoveries | `Type must be 0/1/2` | type 值无效 |
| POST /api/admin/blog | `Title is required` | title 为空 |
| PUT/DELETE /api/admin/blog/{id} | `Blog post not found` | 博客 ID 不存在 |
| PUT/DELETE /api/admin/discoveries/{id} | `Discovery item not found` | 发现 ID 不存在 |
| POST /api/admin/feedback/batch-delete | `No IDs provided` | ids 数组为空 |

## 日志

- 路径: `runtimes/logs/api-YYYY-MM-DD.log`
- 内容: 完整请求/响应 (含 headers, body, 耗时)
- 大文件上传跳过 body 日志
- 可通过 `log_max_bytes` 控制截断

## 特性

- CORS 全开放 (适配管理后台)
- 支持 file 和 url 两种版本类型
- 版本号自动从文件名推断
- CSV 导入导出
- 启动统计 (按平台/版本聚合)
