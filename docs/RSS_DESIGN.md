# Zebra RSS 双方案设计文档

> 设计目标：**本地客户端方案**与**服务器统一管理方案**两套独立存在、互不依赖。
> 本文档对应现有代码盘点：
> - 客户端 `lib/`：9 个 RSS 界面、本地库 `zebra_rss.db`（feed_sources / articles / rss_folders / rss_folder_items）
> - 服务端 `packer/src/rss_server.rs`：`zebra_rss.db`（rss_sources / rss_folders / rss_folder_items）+ 全部现有 /api/rss/* 接口
> - 管理后台 `packer/static/rss_admin.html`（/api/admin/rss 页面）

---

## 第一部分：本地客户端方案（保留全部功能 + 优化）

### 1.1 保留清单（不动的部分）

| 模块 | 现状 | 处理 |
|---|---|---|
| 9 个界面 | 源列表 / 文章列表 / 详情 / 探索 / 源管理 / 快捷添加 / 文件夹管理 / 导入导出 / 设置 | 全部保留 |
| 本地四表 | feed_sources、articles、rss_folders、rss_folder_items | 表结构保留，仅**加列/加索引/加新表**，不删不改 |
| 抓取解析 | `RssRepository` 的 rss1/rss2/atom 解析、编码探测 | 保留 |
| 导入导出 | CSV / OPML 双向 | 保留，增强自动备份 |
| 本地搜索 | 无 | 新增（见 1.3） |
| 自动同步 | `RssProvider._startAutoSync`（默认 30min 定时） | 保留，改并发 + 条件请求 |

### 1.2 数据层优化（`rss_database_service.dart`）

1. **FTS5 全文搜索（新增）**
   - 建虚拟表 `articles_fts`，同步维护标题/摘要/内容索引：
     ```sql
     CREATE VIRTUAL TABLE IF NOT EXISTS articles_fts USING fts5(
       title, summary, content, content='articles', content_rowid='id'
     );
     -- 外部内容表 + 触发器增量维护，避免手动重建
     ```
   - 插入/更新/删除文章时同步更新 FTS（三个触发器）。
   - 新增查询 `searchArticles(keyword, {page, size})`，中文走 `unicode61` 分词。
2. **未读计数优化**
   - 现状 `getUnreadCount` / `getTotalUnreadCount` 每次 COUNT 全表；改为在 `feed_sources` 上加 `unread_count INTEGER DEFAULT 0` 列，由 markAsRead / insertArticle / markAllAsRead 事务内增量维护，查询直接读列（O(1)）。
3. **索引与分页优化**
   - 加组合索引 `idx_articles_feed_read(feed_source_id, is_read)` 支撑未读过滤。
   - 分页从 `OFFSET` 改为 keyset（`WHERE (created_at, id) < (:last_created, :last_id) ORDER BY created_at DESC, id DESC LIMIT n`），深分页不再变慢；`RssProvider` 记录 `_lastCursor`。
4. **文章生命周期（保留现有清理，补自动策略）**
   - 设置页已有"清理 N 天前文章"；新增可选项：订阅源级别保留条数上限（如每源最多 500 条），由清理任务执行。

### 1.3 同步体验优化（`rss_repository.dart` / `rss_provider.dart`）

1. **并发同步**：`syncAllFeedSources` 目前串行 for 循环，改为受限并发（`Future.wait` 分 4 批），整体耗时从 N×2s 降到约 2×ceil(N/4)s；单源超时 15s 不变。
2. **条件请求**：`RssApiService.fetchFeed` 携带 `If-Modified-Since: 上次 last_synced_at`，源返回 304 时跳过解析，省流量省 CPU。
3. **增量同步状态**：`syncFeedSource` 记录每源 `last_synced_at`（已有字段），失败写 `last_sync_error`（已有字段）并在源管理界面红字展示（已有 UI 基础）。
4. **同步进度**：`RssProvider` 增加 `syncingFeedTitle` 与 `syncedCount/totalCount`，源列表顶部显示进度条；同步完成弹出"新增 N 篇"轻提示。
5. **失败重试**：连续失败 3 次的源，自动降级同步频率（每 3 个周期再试一次），避免每次全量重试拖慢整体。

### 1.4 UI 优化（保留现有布局，增强桌面端与可读性）

1. **三栏自适应**：宽屏（>1000dp）下 `RssFeedListScreen` 拆为「源/文件夹栏 + 文章列表 + 详情预览」，窄屏保持现有两栏；复用现有 `isWide` 判断模式。
2. **阅读进度**：详情页记录滚动 offset，返回列表再进入同一文章时恢复位置（`SharedPreferences` 按 articleId 存 `scrollOffset`，上限 200 条 LRU）。
3. **未读徽标实时化**：markAsRead / toggleStar 后直接更新源列表徽标（配合 1.2 的 O(1) 计数）。
4. **桌面快捷键**：`J/K` 上下篇、`R` 标已读、`S` 星标、`Shift+A` 全部已读（在 `RssArticleListScreen`/详情页加 `Focus` + `Shortcuts`）。
5. **图片懒加载与缓存**：详情页 HTML 图片改用 `flutter_html` 的 `onImageTap` 预览 + 加载占位；必要时引入图片缓存（先保持现状，仅加占位）。
6. **空态与错误态完善**：已有 empty/skeleton；补"同步失败"错误条（点击重试该源）。

### 1.5 数据安全（增强）

- **自动备份**：设置页新增"定时备份订阅清单"（默认关，开启后每 7 天把 OPML 备份到 `ApplicationSupportDirectory/backups/`，保留最近 3 份）。
- 本地库加密保持现状（release 模式 `PRAGMA key`）。

---

## 第二部分：服务器统一管理方案

### 2.1 职责定位

服务器成为 RSS 的**统一收口**：统一抓取、统一存文、统一状态、统一管理后台。客户端接入后无需自己抓取，按需拉增量。

与第一部分的边界：本部分服务端能力**独立存在**，不依赖客户端任何改动即可自洽运行（通过 `/api/admin/rss` 后台 + 定时抓取自足）；客户端是否接入由用户在设置中选择（见第三部分）。

### 2.2 服务端数据表扩展（`packer/src/rss_server.rs` `RssDb::open`）

在现有三表基础上新增（`CREATE TABLE IF NOT EXISTS`，老库自动升级）：

```sql
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
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(source_id, guid)
);
CREATE INDEX IF NOT EXISTS idx_rss_articles_source ON rss_articles(source_id);
CREATE INDEX IF NOT EXISTS idx_rss_articles_published ON rss_articles(published_at DESC);

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
    title, summary, content, content='rss_articles', content_rowid='id'
);
-- + 三个触发器：articles 插入/更新/删除时同步 FTS
```

现有 `rss_sources` 表**保持不变**（管理接口、CSV/OPML、收藏夹逻辑全部复用）。

### 2.3 服务端定时抓取（新增 `fetch_worker.rs`）

- tokio 后台任务：`interval` 每 10 分钟扫描 `rss_sources WHERE enabled = 1`，按 `last_fetch_at` 过期（默认 30min）筛选待抓取源。
- 抓取实现：复用 `api_server.rs` 现有的 HTTP 能力（reqwest），带 `ETag / If-Modified-Since`（读 rss_sync_state）；304 只更新 `last_fetch_at`。
- 解析：新增 `feed_parser.rs`（参考客户端 `RssRepository` 的 rss1/rss2/atom 三套解析逻辑，Rust 用 quick-xml 或 xml-rs 实现），插入 `rss_articles`（`INSERT OR IGNORE` 按 guid 去重）。
- 失败处理：写 `rss_sync_state.consecutive_failures`；连续 5 次失败自动跳过该源（标记 `enabled` 不变，仅暂停抓取并在后台展示），下次成功时清零。
- 防护：单请求超时 15s、响应体上限 10MB、并发抓取上限 4、SSRF 防护（仅 http/https）。

### 2.4 REST API 扩展（追加到 `rss_server.rs` 路由，不冲突）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/rss/articles` | 文章分页（?source_id=&page=&size=&search= 走 FTS） |
| GET | `/api/rss/articles/{id}` | 文章详情（含 content 全文） |
| GET | `/api/rss/articles/unread` | 各源未读数汇总（服务端聚合，返回 [{source_id, unread}]） |
| POST | `/api/rss/sync` | 手动触发立即抓取（限流：同一源 10min 内不重复） |
| GET | `/api/rss/sync/status` | 抓取状态（last_fetch_at / last_error / 待抓源数） |
| GET | `/api/admin/rss/articles` | 后台文章列表（分页 + 搜索） |
| DELETE | `/api/admin/rss/articles/{id}` | 后台删除文章 |
| GET | `/api/admin/rss/sync` | 后台查看全部源抓取状态 |
| POST | `/api/admin/rss/sync` | 后台强制触发全量抓取 |

响应统一 `{ success, data, total, page, size }`，与现有接口风格一致。

### 2.5 管理后台扩展（`packer/static/rss_admin.html`）

现有页面已有：源 CRUD、收藏夹、导入导出、从 blog/discoveries/versions 生成源。新增两个 Tab：

1. **文章管理**：分页浏览全部文章（标题/源/时间），搜索框（调 /api/admin/rss/articles?search=），单条删除。
2. **抓取状态**：表格展示每源 last_fetch_at / etag / consecutive_failures / last_error，按钮「立即抓取全部」；红色标记连续失败源。

纯静态页 + fetch，沿用现有 admin 登录鉴权。

### 2.6 客户端 server 模式集成（可选接入，独立于第一部分）

接入时客户端不再自行抓取，改为：

1. **源管理**：源列表改为「拉取服务器源」+「本地源」混合展示；`FeedSource.source` 字段（已有 'local'/'server'）作为区分标志。
2. **文章流**：`RssApiService` 新增 `getArticles(sourceId, page)` 走 `/api/rss/articles`；本地 `articles` 表仅作离线缓存（未读/星标状态以服务端为准，本地同步标记）。
3. **状态同步**：进入 app 时拉 `/api/rss/articles/unread` 刷新未读徽标；标已读/星标后立即 POST 到服务端（新增 `/api/rss/articles/{id}/state` 批量接口：`PATCH {read?, starred?}`），失败进入重试队列。
4. **手动刷新**：调 `/api/rss/sync` 触发服务端抓取，完成后拉增量。

> 注：2.6 是"接入方式"，其本身并不破坏第一部分——客户端两种来源可并存，未配置服务器地址时完全走本地方案。

---

## 第三部分：两套方案独立共存机制

### 3.1 模式开关（设置页新增一节）

- `RssSettingsScreen` 新增「服务器模式」：服务器地址 + 启用开关（存 `SharedPreferences: rss_server_mode / rss_server_url`）。
- **默认关**：全部走本地方案（第一部分），行为与现状完全一致。
- 开启后：源列表/文章列表的数据源切换为 server 优先 + 本地缓存降级（2.6）。

### 3.2 数据隔离

- 本地 `articles` 表继续存本地模式数据；server 模式文章写入**独立命名空间**：`feed_source_id` 为负值映射（`-(serverId)`）或新增 `sync_source` 列，杜绝两套数据互相覆盖。
- `feed_sources.source` 字段区分本地源与服务器源，删除/清理互不影响（`clearHistory` 只清理本地源文章）。
- 未读计数在两种模式下分别维护，切换模式时重新统计，不做跨模式合并。

### 3.3 互不影响保证

- 本地方案的所有优化（1.2/1.3/1.4）不依赖服务端任何接口，离线可用。
- 服务端方案（第二部分）不依赖客户端新代码，可通过后台 + API 独立自洽。
- 唯一共享点是 `RssApiService` 基址（`UpdateService.apiBaseUrl`），server 模式复用该配置，不改动其默认行为。

---

## 第四部分：实施计划

### 4.1 实施顺序（本地方案先行，服务端方案独立并行）

| 阶段 | 内容 | 涉及文件 |
|---|---|---|
| L1 | FTS5 本地搜索 + 未读计数列 + keyset 分页 | `rss_database_service.dart`、`rss_repository.dart`、`rss_provider.dart` |
| L2 | 并发同步 + If-Modified-Since + 重试降级 + 进度展示 | `rss_api_service.dart`、`rss_repository.dart`、`rss_provider.dart` |
| L3 | 三栏自适应、快捷键、阅读进度、未读徽标实时化 | `rss_feed_list_screen.dart`、`rss_article_list_screen.dart`、`rss_article_detail_screen.dart` |
| L4 | 自动备份 OPML | `rss_settings_screen.dart`、`rss_repository.dart` |
| S1 | 服务端：rss_articles + sync_state + FTS 表 | `packer/src/rss_server.rs` |
| S2 | 服务端：feed_parser.rs + fetch_worker.rs 定时抓取 | 新增 `packer/src/feed_parser.rs`、`packer/src/fetch_worker.rs`，`main.rs` 挂载 |
| S3 | 服务端：文章/未读/同步 REST API | `packer/src/rss_server.rs` 路由追加 |
| S4 | 后台两个新 Tab | `packer/static/rss_admin.html` |
| C1 | 客户端 server 模式（源拉取、文章流、状态同步、切换开关） | `rss_api_service.dart`、`rss_provider.dart`、`rss_settings_screen.dart` |

### 4.2 验收标准

- 本地方案：断网状态下 9 屏全部可用；千篇文章搜索 <100ms；同步全部源耗时较现状明显下降。
- 服务端方案：后台可看文章/抓取状态；`/api/rss/articles` 分页与搜索正确；连续失败源被自动暂停。
- 共存：两种模式数据互不覆盖，切换模式不丢数据、不错乱。
