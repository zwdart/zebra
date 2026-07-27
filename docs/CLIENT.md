# Zebra Flutter 客户端

Flutter 跨平台应用，集成 RSS 阅读器、SSH 终端、SFTP、日记等功能。

## 技术栈

- **框架**: Flutter (Dart SDK ^3.11.4)
- **状态管理**: Provider
- **SSH**: dartssh2 + xterm
- **数据库**: sqlite3 + sqlite3_flutter_libs
- **平台**: Android / iOS / Windows / macOS / Linux / Web

## 项目结构

```
lib/
├── main.dart                 # 应用入口
├── build_info.dart           # 构建信息
├── database/
│   ├── database_service.dart     # 主数据库 (connections, diary)
│   └── rss_database_service.dart # RSS 独立数据库 (feed_sources, articles, folders)
├── models/
│   ├── ssh_connection.dart       # SSH 连接模型
│   ├── terminal_session.dart     # 终端会话模型
│   ├── sftp_file_item.dart       # SFTP 文件模型
│   ├── blog_post.dart            # 博客文章模型
│   ├── diary_entry.dart          # 日记模型
│   ├── discovery_item.dart       # 发现内容模型
│   ├── feedback_item.dart        # 反馈模型
│   ├── linux_command.dart        # Linux 命令模型
│   ├── feed_source.dart          # RSS 订阅源模型
│   └── rss_article.dart          # RSS 文章模型
├── providers/
│   ├── connection_provider.dart      # SSH 连接管理
│   ├── ssh_provider.dart             # SSH 状态
│   ├── sftp_provider.dart            # SFTP 状态
│   ├── theme_provider.dart           # 主题
│   ├── locale_provider.dart          # 国际化
│   ├── monitor_provider.dart         # 系统监控
│   ├── process_provider.dart         # 进程管理
│   ├── cleanup_provider.dart         # 磁盘清理
│   ├── update_provider.dart          # 更新检查
│   ├── linux_command_provider.dart   # Linux 命令
│   └── rss_provider.dart             # RSS 状态 (feeds, articles, folders)
├── services/
│   ├── ssh_service.dart              # SSH 核心服务
│   ├── sftp_service.dart             # SFTP 服务
│   ├── update_service.dart           # 版本更新 & API 调用
│   ├── blog_service.dart             # 博客服务
│   ├── discovery_service.dart        # 发现服务
│   ├── feedback_service.dart         # 反馈服务
│   ├── compression_service.dart      # 压缩/解压
│   ├── window_service.dart           # 窗口管理
│   └── rss_api_service.dart          # RSS API (服务器同步收藏夹)
├── repositories/
│   └── rss_repository.dart           # RSS 数据仓库 (DB + CSV/OPML)
├── screens/
│   ├── shell_screen.dart             # 底部导航外壳 (RSS/SSH/日记/设置 四 Tab)
│   ├── home_screen.dart              # SSH 首页 (连接列表)
│   ├── terminal_screen.dart          # SSH 终端 (多标签)
│   ├── sftp_screen.dart              # SFTP 文件管理
│   ├── monitor_screen.dart           # 系统资源监控
│   ├── process_screen.dart           # 进程查看/终止
│   ├── cleanup_screen.dart           # 磁盘清理
│   ├── connection_form_screen.dart   # 连接编辑表单
│   ├── settings_screen.dart          # 设置 (含 RSS 源管理入口)
│   ├── diary_screen.dart             # 本地日记
│   ├── blog_screen.dart              # 在线博客浏览
│   ├── discovery_screen.dart         # 推荐内容
│   ├── feedback_screen.dart          # 提交反馈
│   ├── about_screen.dart             # 关于
│   ├── update_dialog.dart            # 更新弹窗
│   ├── linux_commands_screen.dart    # 常用 Linux 命令
│   └── rss/                          # RSS 模块页面
│       ├── rss_feed_list_screen.dart     # RSS 源列表 & 收藏列表
│       ├── rss_article_list_screen.dart  # 全部文章 / 星标列表
│       ├── rss_article_detail_screen.dart# 文章详情 (Markdown 渲染)
│       ├── rss_source_manage_screen.dart # 订阅源管理
│       ├── rss_quick_add_screen.dart     # 快速添加订阅源
│       ├── rss_folder_manage_screen.dart # 收藏夹分组管理
│       ├── rss_import_export_screen.dart # 导入导出 (CSV/OPML)
│       └── rss_settings_screen.dart      # RSS 设置
├── widgets/                  # 通用组件 (CustomTitleBar, ConnectionCard 等)
├── theme/                    # 主题配置
├── l10n/                     # 国际化资源
└── utils/                    # 工具函数
    ├── zebra_paths.dart          # 共享存储路径管理
    └── unique_id.dart            # 设备唯一标识
```

## 数据库

### 主数据库 `zebra.db`

路径: `{appSupportDir}/zebra/zebra.db`

#### connections - SSH 连接

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| name | TEXT | - | 连接名称 (必填) |
| host | TEXT | - | 服务器地址 (必填) |
| port | INTEGER | 22 | SSH 端口 |
| username | TEXT | - | 登录用户名 (必填) |
| auth_type | TEXT | 'password' | 认证方式: password 或 key |
| password | TEXT | NULL | 密码 (password 模式) |
| private_key_path | TEXT | NULL | 私钥文件路径 (key 模式) |
| passphrase | TEXT | NULL | 私钥口令 (可选) |
| remark | TEXT | NULL | 备注 |
| created_at | TEXT | - | 创建时间 (ISO 8601) |
| updated_at | TEXT | - | 更新时间 (ISO 8601) |

#### diary - 日记

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| title | TEXT | '' | 标题 |
| content | TEXT | '' | 内容 |
| mood | TEXT | 'neutral' | 心情: happy/neutral/sad/angry/excited |
| created_at | TEXT | - | 创建时间 (ISO 8601) |
| updated_at | TEXT | - | 更新时间 (ISO 8601) |

### RSS 数据库 `zebra_rss.db`

路径: `{appSupportDir}/zebra/zebra_rss.db` — 独立 SQLite 数据库

#### feed_sources - 订阅源

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| title | TEXT | '' | 源名称 |
| url | TEXT | - | Feed URL (唯一索引) |
| site_url | TEXT | '' | 网站链接 |
| feed_type | TEXT | 'rss2' | 类型: rss1/rss2/atom |
| icon_url | TEXT | '' | 图标 URL |
| category | TEXT | '' | 分类 |
| last_synced_at | TEXT | NULL | 上次同步时间 |
| sync_enabled | INTEGER | 1 | 是否启用同步 |
| sort_order | INTEGER | 0 | 排序权重 |
| source | TEXT | 'local' | 来源: local/server |
| last_sync_error | TEXT | NULL | 最近一次同步错误信息 |
| created_at | TEXT | datetime('now') | 创建时间 |
| updated_at | TEXT | datetime('now') | 更新时间 |

索引: `idx_feed_sources_url` (唯一), `idx_feed_sources_synced`, `idx_feed_sources_last_sync_error`

#### articles - 文章

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| feed_source_id | INTEGER | - | 所属源 ID (外键) |
| guid | TEXT | '' | 文章唯一标识 |
| title | TEXT | '' | 标题 |
| link | TEXT | '' | 原文链接 |
| author | TEXT | '' | 作者 |
| summary | TEXT | '' | 摘要 |
| content | TEXT | '' | 全文内容 (HTML/Markdown) |
| published_at | TEXT | NULL | 发布时间 |
| is_read | INTEGER | 0 | 是否已读 |
| is_starred | INTEGER | 0 | 是否收藏 |
| created_at | TEXT | datetime('now') | 入库时间 |

索引: `idx_articles_feed`, `idx_articles_published`, `idx_articles_read`, `idx_articles_starred`, `idx_articles_feed_guid` (唯一)

#### rss_folders - 收藏夹

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| name | TEXT | - | 文件夹名称 |
| description | TEXT | '' | 描述 |
| created_at | TEXT | datetime('now') | 创建时间 |
| updated_at | TEXT | datetime('now') | 更新时间 |

#### rss_folder_items - 收藏夹-源关联

| 列名 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 主键 |
| folder_id | INTEGER | 外键 → rss_folders.id, ON DELETE CASCADE |
| source_id | INTEGER | 外键 → feed_sources.id, ON DELETE CASCADE |
| created_at | TEXT | 关联时间 |

唯一约束: `(folder_id, source_id)`

**自动种子**: 首次启动且数据库为空时，自动插入 5 个默认源 + 创建"默认"收藏夹 (含前 3 个源):
1. 别的 — `biede.com/feed/`
2. 虎嗅网 — `rss.huxiu.com`
3. Nature — `nature.com/nature.rss`
4. 美团技术 — `tech.meituan.com/rss.xml`
5. 钛媒体 — `tmtpost.com/feed`

## 架构与核心模块

```
ShellScreen (四 Tab 导航)
├── Tab 1: RSS (NavigationRail / NavigationBar)
│   └── RssFeedListScreen
│       ├── 源列表视图 (Provider.loadFeedSources())
│       └── 收藏夹视图 (Provider.loadFolderArticles(folderId))
│   └── RSS 模块 9 个子页面
├── Tab 2: SSH (HomeScreen)
│   ├── 连接列表 → TerminalScreen / SftpScreen
│   ├── MonitorScreen / ProcessScreen / CleanupScreen
│   └── LinuxCommandsScreen
├── Tab 3: 日记 (DiaryScreen)
│   └── CRUD + mood 筛选 + CSV 导出
└── Tab 4: 设置 (SettingsScreen)
    ├── 主题 / 语言 / 更新设置
    ├── RSS 源管理 / 收藏夹 / 导入导出
    └── 博客 / 发现 / 反馈 / 关于
```

### RSS 功能 (`rss_provider.dart`)

- **状态管理**: `ChangeNotifier` + `RssRepository`
- **自动同步**: 每 30 分钟调用 `syncAll()`
- **数据流**: Provider → Repository → RssDatabaseService
- **服务器同步**: 从后端 `/api/rss/folders` 和 `/api/rss/sources` 获取远程收藏夹 (通过 `RssApiService`)

**Provider 主要方法**:

| 方法 | 说明 |
|------|------|
| `loadFeedSources()` | 加载全部订阅源 |
| `addFeedSource(FeedSource)` | 手动添加源 |
| `addFeedSourceFromUrl(String, {title})` | 从 URL 添加并立即抓取 |
| `deleteFeedSource(int)` | 删除源 (级联删除文章) |
| `loadArticles(int, {refresh})` | 加载某源的文章列表 |
| `loadAllArticles({refresh})` | 加载全部文章 |
| `loadStarredArticles({refresh})` | 加载星标文章 |
| `loadFolderArticles(int, {refresh})` | 按收藏夹加载文章 |
| `markAsRead(int)` | 标记已读 |
| `toggleStar(int)` | 切换收藏 |
| `syncAll()` / `syncFeedSourceById(int)` | 手动同步 |
| `clearHistory({feedSourceId, before})` | 清除历史 |
| `exportToCsv()` / `exportToOpml()` | 导出数据 |
| `importFromCsv(String)` / `importFromOpml(String)` | 导入数据 |

### SSH 服务 (`ssh_service.dart`)

- 支持密码和密钥两种认证方式
- 多终端会话 (每个终端独立 PTY)
- 终端窗口大小动态调整

### 系统监控

- CPU / 内存 / 磁盘使用率
- 进程列表查看和管理
- 磁盘清理建议

## 共享存储路径

`ZebraPaths` 统一管理所有共享存储路径，基于 `getApplicationDocumentsDirectory()`:

```
{documentsDir}/zebra.dart.xin/
├── rss/      # RSS 导入导出文件
├── diary/    # 日记 CSV 导出
└── ssh/      # SSH 下载文件
```

数据库存储在 `{appSupportDir}/zebra/`:
- `zebra.db` — 主数据库
- `zebra_rss.db` — RSS 数据库

## 页面功能

| 页面 | 模块 | 功能 |
|------|------|------|
| ShellScreen | 全局 | IndexedStack 四 Tab (RSS/SSH/日记/设置)，桌面端 NavigationRail，移动端 NavigationBar |
| HomeScreen | SSH | 连接列表、搜索、新增/编辑/删除 |
| TerminalScreen | SSH | SSH 终端 (多标签) |
| SftpScreen | SSH | 文件管理、上传下载 (支持拖拽) |
| MonitorScreen | 系统 | 系统资源监控 |
| ProcessScreen | 系统 | 进程查看/终止 |
| CleanupScreen | 系统 | 磁盘清理 |
| DiaryScreen | 日记 | 本地日记 CRUD、mood 筛选、CSV 导出导入 |
| BlogScreen | 博客 | 在线博客浏览、Markdown 渲染 |
| DiscoveryScreen | 发现 | 推荐内容浏览 |
| FeedbackScreen | 反馈 | 提交反馈 (邮箱限流 30min) |
| SettingsScreen | 全局 | 主题/语言/更新/RSS 管理入口 |
| AboutScreen | 关于 | 关于信息 |
| UpdateDialog | 全局 | 更新提示弹窗 (支持强制更新/跳过7天) |
| LinuxCommandsScreen | 系统 | 常用 Linux 命令参考 |
| RssFeedListScreen | RSS | 订阅源列表 + 收藏夹列表 (两 Tab) |
| RssArticleListScreen | RSS | 全部文章 / 星标文章分页列表 |
| RssArticleDetailScreen | RSS | 文章详情 (Markdown 渲染) |
| RssSourceManageScreen | RSS | 订阅源增删改查、同步控制 |
| RssQuickAddScreen | RSS | 快速添加订阅源 URL |
| RssFolderManageScreen | RSS | 收藏夹分组管理、源拖入/移除 |
| RssImportExportScreen | RSS | CSV / OPML 导入导出 |
| RssSettingsScreen | RSS | RSS 同步设置 |

## 桌面 CustomTitleBar

桌面端使用自定义标题栏 `CustomTitleBar`，替代系统原生标题栏，提供窗口控制 (最小化/最大化/关闭)。

## 异常处理

### SSH 连接异常

| 异常 | 处理方式 |
|------|----------|
| 连接超时 | 提示检查网络 |
| 认证失败 | 提示重新输入密码/密钥 |
| 连接断开 | 终端显示关闭提示 |
| 私钥文件不存在 | 提示检查配置 |

### SFTP 异常

- 文件操作失败: 显示具体错误 (权限不足、文件不存在等)
- 上传/下载中断: 保留已传输部分，允许重试

### 更新异常

- 静默检查更新，跳过期 7 天
- 下载失败: 提示重试，不自动重试

### RSS 同步异常

- 同步失败: 记录 `last_sync_error` 到源记录
- 网络错误: debugPrint 输出，不影响正常使用

## 依赖说明

| 包 | 用途 |
|---|------|
| dartssh2 | SSH 协议实现 |
| xterm | 终端渲染 |
| sqlite3 | 本地数据库 |
| sqlite3_flutter_libs | SQLite 库绑定 |
| provider | 状态管理 |
| file_picker | 文件选择 |
| desktop_drop | 拖拽上传 |
| share_plus | 分享功能 |
| window_manager | 桌面窗口控制 |
| contextmenu | 右键菜单 |
| http | HTTP 请求 |
| package_info_plus | 应用信息 |
| shared_preferences | 本地配置持久化 |
| path_provider | 应用目录路径 |
| path | 路径拼接 |
| url_launcher | 打开外部链接 |
| flutter_html | HTML 渲染 |
| markdown | Markdown 渲染 |
| archive | 文件压缩/解压 |
| cupertino_icons | 图标资源 |
| xml | XML 解析 (RSS feed) |

## 国际化

支持中文和英文，通过 `l10n/` 目录管理翻译资源。使用 `AppLocalizations` 类访问本地化字符串。

## 主题

支持亮色/暗色主题切换，通过 `ThemeProvider` 管理。桌面端使用自定义标题栏。
