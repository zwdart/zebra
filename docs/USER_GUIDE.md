# Zebra 客户端功能说明与操作使用文档

> 适用对象：Zebra 客户端（`lib/`）的使用者与维护者
> 平台：桌面端 Windows / macOS / Linux（PC）与移动端 Android / iOS
> 文档基线：随代码持续更新；文中路径均相对项目根目录 `zebra/`

Zebra 是一个跨平台客户端，包含五大功能块：**SSH/SFTP、RSS 阅读、日记、局域网聊天与文件传输**，并附带二维码工具、Linux 命令参考、博客/发现、系统监控与设置等辅助功能。本文档按功能块组织，区分 PC（桌面）端与移动端操作差异。

---

## 目录

- [1. 客户端总览](#1-客户端总览)
- [2. 平台差异说明（PC vs 移动端）](#2-平台差异说明pc-vs-移动端)
- [3. SSH 远程终端与 SFTP 文件管理](#3-ssh-远程终端与-sftp-文件管理)
- [4. RSS 阅读（本地订阅 + 服务器模式）](#4-rss-阅读本地订阅--服务器模式)
- [5. 日记](#5-日记)
- [6. 局域网聊天与文件传输](#6-局域网聊天与文件传输)
- [7. 设置、存储与数据管理](#7-设置存储与数据管理)
- [8. 其它工具（二维码 / 命令参考 / 发现）](#8-其它工具二维码--命令参考--发现)
- [9. 数据与配置存储位置](#9-数据与配置存储位置)

---

## 1. 客户端总览

### 1.1 主界面结构

应用启动后无登录页，直接进入 **Shell 壳界面**（`lib/screens/shell_screen.dart`），底部/侧边共 5 个固定主 Tab：

| 序号 | Tab | 页面 | 图标 |
|---|---|---|---|
| 0 | RSS | `RssFeedListScreen`（本地模式）或 `RssServerHomeScreen`（服务器模式） | rss_feed |
| 1 | SSH | `HomeScreen`（连接管理列表） | computer |
| 2 | 聊天 | `LanChatHomeScreen`（局域网聊天） | chat |
| 3 | 日记 | `DiaryScreen` | book |
| 4 | 设置 | `SettingsScreen` | settings |

- **桌面端**：左侧 `NavigationRail` + 垂直分隔线 + 内容区（`shell_screen.dart:94-144`），无边框窗口 + 自绘标题栏。
- **移动端**：内容区为 `IndexedStack`（切 Tab 不销毁页面状态）+ 底部 `NavigationBar`（`shell_screen.dart:147-159`）。

### 1.2 平台判断方式

代码中**不使用** `TargetPlatform`，而是：

```dart
// lib/widgets/custom_title_bar.dart:28
static bool get isDesktop => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
```

- `isDesktop == true`：Windows / macOS / Linux → 无边框窗口、自绘标题栏、左侧导航栏、支持拖拽/右键等桌面交互。
- `isDesktop == false`：Android / iOS（及 Web）→ 原生 AppBar、底部导航栏、触摸交互。

### 1.3 页面路由

未使用 go_router，全部为 `MaterialPageRoute` 栈式跳转，仅 5 个命名路由（`lib/main.dart:174-180`）：

```
/terminal  → TerminalScreen   （SSH 终端）
/sftp      → SftpScreen       （SFTP 文件管理）
/monitor   → MonitorScreen    （服务器监控）
/processes → ProcessScreen    （进程列表）
/cleanup   → CleanupScreen    （磁盘清理）
```

其余页面均由 `Navigator.push(MaterialPageRoute(...))` 进入。

---

## 2. 平台差异说明（PC vs 移动端）

| 维度 | 桌面端（Windows/macOS/Linux） | 移动端（Android/iOS） |
|---|---|---|
| 窗口 | 无边框窗口 + 自绘标题栏（最小化/最大化/关闭，可拖拽区域） | 全屏原生界面 |
| 主导航 | 左侧 NavigationRail（`shell_screen.dart:94-144`） | 底部 NavigationBar（`shell_screen.dart:147-159`） |
| 终端交互 | 右键弹出 Tab 菜单、中键关闭 Tab、硬件键盘（`terminal_screen.dart:254-268, 633`） | 长按 Tab 出菜单、选择浮层（`terminal_screen.dart:270-279, 541-599`） |
| 终端字体 | Windows 使用 Consolas（`terminal_screen.dart:637`） | 默认等宽字体 |
| 窗口缩放热区 | 仅 Windows 生效（`widgets/window_resize_edges.dart:28`） | 不适用 |
| 文件选择 | `file_picker`（可选路径/读取流）；聊天窗/SFTP 支持**拖拽**上传（`desktop_drop`） | 系统文件选择器；聊天走**原生直读流**（`NativeFileStream`，SAF/UIDocumentPicker，`chat_screen.dart:307-324`） |
| 聊天接收落地 | 文档目录 `zebra_received/`（`receive_directory.dart:55-70, 114`） | Android：MediaStore 系统「下载」目录，免权限（`receive_directory.dart:31-49`）；iOS：文档目录 |
| 传输时防息屏 | 不适用 | 仅 Android/iOS（`services/screen_keep_on.dart`） |
| 卸载入口 | 仅 Linux 显示「从系统卸载」（`settings_screen.dart:176`） | 不适用 |
| RSS 宽屏 | 宽度 >1000 显示三栏（源列表 + 文章 + 预览，`rss_feed_list_screen.dart:56, 153`） | 单栏堆叠 |
| 权限 | 无特殊权限；数据库/文件均在应用支持目录 | 免运行时权限设计：文件走 MediaStore/文档目录，局域网用本机 socket，无需申请定位/存储权限 |

> 共同点：两端功能集一致（全部 5 个功能块都可用），差异仅在交互方式与文件落盘位置。

---

## 3. SSH 远程终端与 SFTP 文件管理

### 3.1 功能说明

通过 SSH 连接远程服务器，提供：**终端多标签会话**、**SFTP 文件浏览/传输/编辑**、**服务器监控（CPU/内存/磁盘）、进程管理与磁盘清理**。底层基于 `dartssh2`，SFTP 子功能复用同一条 SSH 连接（`services/ssh_service.dart:173` `sftp()`）。

- 连接信息（主机/端口/用户/认证）持久化在本地 SQLite `connections` 表（release 构建带库加密，`database_service.dart:32-35`）。
- 密码认证：`SshService.connect`（`ssh_service.dart:27-68`）；密钥认证：`SSHKeyPair.fromPem` 读本地私钥文件。
- 会话数上限 10 个 Tab（`providers/ssh_provider.dart` `maxSessions = 10`）。

### 3.2 操作文档

#### 3.2.1 添加 / 编辑连接

入口：SSH Tab → 右上角 **「+」（新建连接）**；已有连接点卡片上的编辑图标。

表单字段（`connection_form_screen.dart`）：

1. **名称**（必填）— 自定义标识，如「生产服务器」。
2. **主机**（必填）— IP 或域名。
3. **端口**（默认 22）— 1~65535。
4. **用户名**（必填）。
5. **认证方式**（分段按钮二选一）：
   - **密码认证**：输入密码（可点眼睛图标切换明文/密文）。
   - **密钥认证**：填写/选择**私钥路径**（点文件夹图标用系统文件选择器选择），可选**密钥口令**。
6. **备注**（可选，最多 3 行）。
7. 点右上角 **「保存」** 完成。

#### 3.2.2 连接与断开

- 在连接列表点 **「连接」**（`home_screen.dart:203`）：显示「正在连接…」，成功后自动进入终端页；失败则 SnackBar 提示错误原因。
- 连接卡片上还有两个快捷按钮：**「文件」**（直接进入 SFTP，自动连接）与 **「监控」**（直接进入监控页，自动连接）（`home_screen.dart:245-329`）。
- 终端页右上角 **「重新连接」**（`Icons.refresh`）可断开并重连。

#### 3.2.3 终端操作（TerminalScreen）

- **多标签**：标题栏 **「+」** 新建会话；点击 Tab 切换；每个 Tab 显示会话名。
- **关闭 Tab**：Tab 上的 ✕ 图标；桌面额外支持右键菜单（关闭 / 关闭其它 / 关闭全部）与中键直接关闭（`terminal_screen.dart:254-268`）。
- **输入**：桌面直接键入命令回车执行；移动端终端区可点唤出键盘，支持选择浮层复制文本。
- **常用快捷键（终端内）**：`Ctrl+C` 中断、`Ctrl+L` 清屏、`Ctrl+D` 发送 EOF、终端内复制/粘贴走 `Ctrl+Shift+C/V`（Windows 为 `Ctrl+Shift+C`）。
- 断线时页面显示「连接出错 + 重新连接」按钮（`terminal_screen.dart:134-152`）。
- 终端页右上角：**「+」**（新 Tab）/ 心形图标（监控）/ 文件复制图标（SFTP）/ 刷新（重连）。

#### 3.2.4 SFTP 文件管理（SftpScreen）

入口：连接卡片「文件」按钮，或终端页 SFTP 图标；进入后自动复用已建立的 SSH 连接挂载 SFTP（`sftp_screen.dart:139-153`）。

| 操作 | 桌面端 | 移动端 |
|---|---|---|
| 浏览目录 | 点击文件夹进入；标题栏显示当前路径；左上返回键走路径历史（`navigateTo/goBack`） | 同左 |
| 上传 | 菜单「上传」用文件选择器；**也可直接把文件拖进窗口**（`desktop_drop`，`sftp_screen.dart:259`） | 菜单「上传」 |
| 下载 | 点击文件下载；进度条 + 可取消 | 同左 |
| 排序 | 菜单「排序」：按名称 / 大小 / 修改时间，升/降序切换（`sftp_screen.dart:96-137`） | 同左（底部弹出） |
| 搜索 | 顶部搜索框按文件名过滤 | 同左 |
| 新建目录 | 菜单「新建目录」并输入名称 | 同左 |
| 多选操作 | 长按/点击选择文件 → 出现「全选/取消/删除/压缩」按钮；压缩通过远端执行 `tar czf` 或 `zip -r`（`compression_service.dart`） | 同左 |
| 远端复制/剪切/粘贴 | 复制/剪切后出现粘贴按钮，粘贴即远端执行 `cp -r` / `mv`（`sftp_screen.dart:36-37` 剪贴板状态） | 同左 |
| 编辑/查看文件 | 点击文件预览；小文件（≤5MB，`sftp_service.dart`）可在线编辑保存 | 同左 |
| 原始/可读值切换 | 标题栏魔法棒图标切换「显示原始值/显示转换值」（文件大小、时间显示） | 同左 |
| 在此打开终端 | 菜单「在此打开终端」→ 跳转 `/terminal` | 同左 |
| 跳转到指定路径 | 菜单「导航到路径」输入绝对路径跳转 | 同左 |

#### 3.2.5 监控、进程与清理

入口：连接卡片「监控」或终端页心形图标。

- **监控页**（`monitor_screen.dart`）：CPU、内存、磁盘使用率实时图表；可跳转「进程列表」（`/processes`，可结束进程）与「磁盘清理」（`/cleanup`，按目录统计大小并可清理）。

### 3.3 导入 / 导出连接

SSH Tab 右上角菜单：

- **导出 CSV**：所有连接导出为 `ssh_connections_<时间戳>.csv`，保存到 `zebra` 应用文档目录 `ssh/` 下，弹窗显示路径，可点「分享」调起系统分享（`home_screen.dart:343-406`）。
- **导入 CSV**：选择 CSV 文件批量导入，字段顺序固定为
  `name,host,port,username,auth_type,password,private_key_path,passphrase,remark`
  （`home_screen.dart:408-458`）。

---

## 4. RSS 阅读（本地订阅 + 服务器模式）

### 4.1 功能说明

RSS Tab 提供两种数据模式（`providers/rss_provider.dart:34` `_serverMode` 开关）：

| 模式 | 说明 | 主页面 |
|---|---|---|
| **本地模式** | 订阅源存本地 `zebra_rss.db`，App 定时抓取 XML/OPML，文章离线可读 | `RssFeedListScreen` |
| **服务器模式** | 连接远端 RSS 服务器（如 `https://zebra.dart.xin`），从服务器拉文章/未读汇总，与本地数据隔离 | `RssServerHomeScreen` |

本地模式核心能力（`rss_provider.dart` / `repositories/rss_repository.dart`）：

- **订阅源管理**：增删改、快速添加（贴 URL 自动识别标题）。
- **文件夹分组**：`RssFolderManageScreen` 管理分组，源可归入文件夹。
- **文章列表**：按源/文件夹/全部/星标分页浏览（keyset 分页）。
- **全文搜索**：标题 + 正文本地搜索。
- **定时同步**：默认 30 分钟，可选 15/30/60/120 分钟。
- **自动备份**：定期备份 `zebra_rss.db`；也可立即备份。
- **导入/导出**：OPML、CSV 双向。
- **历史清理**：按 7 天 / 30 天 / 全部清理文章。

服务器模式额外：

- **同步服务器源到本地**：选择时间窗（7/30 天），把本地已订阅源对应服务器文章拉回本地库离线阅读（`rss_settings_screen.dart:132-183`）。

### 4.2 操作文档

#### 4.2.1 本地模式

1. 进入 RSS Tab（默认本地模式），宽屏（>1000px）为「源列表 + 文章 + 预览」三栏；移动端/窄屏为堆叠列表（`rss_feed_list_screen.dart:56`）。
2. **添加订阅**：菜单 → 「快速添加」（`RssQuickAddScreen`）粘贴 URL；或「订阅源管理」（`RssSourceManageScreen`）逐条编辑。
3. **阅读**：点击源 → `RssArticleListScreen` 文章列表 → 点击文章 → `RssArticleDetailScreen` 详情（`flutter_html` 渲染，正文 >600px 宽显示侧栏）。
4. **星标**：文章页星标后进入「已星标」视图；**文件夹**：菜单「文件夹管理」。
5. **搜索**：列表顶部搜索框全文检索。
6. **OPML 导入/导出**：菜单「导入/导出」（`RssImportExportScreen`）。
7. **发现/推荐**：菜单「发现」（`RssExploreScreen`，推荐/发现/博客 3 Tab）。
8. **快捷键（桌面宽屏）**：`J`/`K` 上下移动、`R` 标记已读、`S` 星标（`rss_feed_list_screen.dart` 快捷键区）。

#### 4.2.2 服务器模式

1. RSS 菜单 → 「设置」（`RssSettingsScreen`）→ 打开 **「服务器模式」** 开关。
2. 输入 **服务器 URL**（默认 `https://zebra.dart.xin`），确认后自动跳转到 `RssServerHomeScreen`。
3. 服务器主页展示远端未读汇总/文章；关闭开关则回本地模式。
4. 「同步到本地」区：选 7 天/30 天窗口 → 点「同步到本地」，把本地已订阅源对应的服务器文章拉回本地（离线后可读）。

#### 4.2.3 设置页全部项（`rss_settings_screen.dart`）

- **服务器模式**：开关 + URL。
- **同步到本地**：时间窗（7/30 天）+ 立即同步按钮。
- **自动备份**：开关 + 「立即备份」。
- **同步间隔**：15 / 30 / 60 / 120 分钟（默认 30）。
- **历史清理**：清 7 天 / 清 30 天 / 清全部（二次确认）。

#### 4.2.4 常见问题

- **同步失败**：检查网络；源 URL 可达；RSS XML 是否标准。
- **服务器模式无数据**：确认 URL 正确、服务器可达；本地订阅源在服务器端存在同名源。
- **文章打不开**：本地模式文章存本地库，服务器模式需联网；服务器「同步到本地」后即可离线。

---

## 5. 日记

### 5.1 功能说明

本地存储的私人日记，数据存于主 SQLite `diary` 表（`database_service.dart:54-63`），每条含**标题、正文、心情**（`models/diary_entry.dart`：happy / neutral / sad / angry / excited 五档）。CRUD、搜索、CSV 导入导出由 `providers/diary_provider.dart` 管理。

### 5.2 操作文档

入口：日记 Tab（主界面第 4 项）；或 设置页 → 「日记」（`settings_screen.dart:86-96`）。

#### 5.2.1 列表页（DiaryScreen）

- 顶部**搜索框**：按标题/正文实时过滤。
- **新建**：标题栏「+」（桌面/移动端均有）→ 进入 `DiaryEditScreen`。
- 卡片显示：心情 emoji + 标题 + 正文摘要（3 行内）+ 时间戳 + 心情标签。
- **编辑**：点击卡片进入编辑页。
- **删除**：长按卡片（`diary_screen.dart:289`）→ 二次确认。
- **导出 CSV / 导入 CSV**：右上角菜单；导出文件存 `diary/` 目录，可「分享」；导入选择文件后提示导入条数（`diary_screen.dart:109-161, 349-365`）。
- **发现入口**：菜单「发现」（`RssExploreScreen(initialTab:1)`，`diary_screen.dart:163-168`）。

#### 5.2.2 编辑页（DiaryEditScreen）

- **心情**：横向 chip 选择（默认 neutral）。
- **标题**：单行（可空）。
- **正文**：多行。
- **保存**：新建走 `insertEntry`，编辑走 `updateEntry`（保留原 `createdAt`，`diary_screen.dart:75-82`）。

---

## 6. 局域网聊天与文件传输

### 6.1 功能说明

在同一局域网内与多台 Zebra 客户端**即时聊天**、**收发文件**、**创建/加入聊天室**。无账号、无公网，纯局域网 P2P。代码位于 `lib/features/lan_chat/`（独立模块）。

#### 6.1.1 设备发现（UDP）

- **服务**：`services/lan_discovery_service.dart`。App 启动即开始，每 **3 秒**广播一次心跳。
- **双通道**：受限广播 `255.255.255.255` + 组播 `239.255.0.250`（`joinMulticast`，解决多设备同时搜索时广播互斥，`lan_discovery_service.dart:186-197`）。
- **心跳内容**：`{deviceId, name, port(TCP聊天端口), room?}`。`deviceId` 为持久化 UUID（`main.dart:52`），`name` 默认为系统主机名（可改）。
- **离线判定**：10 秒周期检查，3 次心跳未收到判离线（`lan_discovery_provider.dart:63`）。
- **开关**：聊天首页右上角 WiFi 图标可启用/停止发现。

#### 6.1.2 端口

| 用途 | 协议 | 默认端口 | 说明 |
|---|---|---|---|
| 发现（心跳） | UDP | **19422** | 两端需一致；可改，改后每天提醒一次并支持一键重置（`lan_chat_home_screen.dart:42-73`） |
| 单聊 | TCP | **22066** | 实际端口随心跳广播，**无需两端一致** |
| 聊天室 | TCP | **22088** | 与单聊错开；成员直连房主（星型） |
| 端口冲突回退 | — | 自动 | 监听被占时顺序尝试 20 个候选，全占则随机空闲端口，并回写心跳（`chat_server.dart:130-145`） |

> 修改发现端口入口：设置页 → 「发现端口」（`settings_screen.dart:241`），输入 1~65535，留空恢复默认；保存后自动重启发现服务。

#### 6.1.3 单聊协议（TCP 自定义帧）

`services/chat_server.dart` / `chat_client.dart`，每端同时是 server（监听）和 client（连对方），双向：

- **帧格式**：1 字节类型 + 4 字节大端长度（TLV）。
  - `0x4A`（'J'）：JSON 消息；`0x47`（'G'）：文件数据块（带 `transferId`，支持同连接并发多文件）。
- **JSON 消息类型**：`hello`（握手）/ `text` / `system` / `file_meta` / `file_ready` / `file_cancel` / `file_done`（带 MD5）/ `file_error`（`chat_server.dart:564-602`）。
- **文件传输流程**：发 `file_meta` → 收 `file_ready`（30s 超时兜底）→ 1MB 分块 → `file_done` 附 MD5。原始字节直传，不压缩、无断点续传（简化方案）。
- **背压**：接收端 64MB 软上限 / 24MB 高水位触发 socket pause/resume（`chat_provider.dart:37-41`）；发送串行。
- **小文件**（≤2MB，`file_transfer_session.dart:5`）走内存快速通道。

#### 6.1.4 聊天室（星型拓扑）

- **房主**（`room_host.dart`）：独立 TCP server，默认端口 22088，上限 50 人，单条消息 64KB。
- **成员**（`room_client.dart`）：直连房主；断线自动重连（最多 40 次 × 3s，`room_provider.dart:44-51`）。
- **房间发现**：复用 UDP 心跳的 `room` 摘要（`RoomInfo`），「附近房间」即其它设备心跳携带的房间（`room_list_screen.dart:179-219`）。
- **消息类型**：`room_join` / `join_ack` / `join_reject` / `room_message` / `room_leave` / `room_close`。

#### 6.1.5 文件落地目录（`receive_directory.dart`）

| 平台 | 接收文件落地位置 |
|---|---|
| Android | 系统「下载」目录（MediaStore，免权限，`receive_directory.dart:31-49`） |
| 桌面 / iOS | 应用文档目录 `zebra_received/`（`zebra_paths.dart`） |

- 传输中先写 `<文件名>.<transferId>.part`，完成后转正（`receive_directory.dart:91-154`）。
- 发送侧：移动端用原生直读流（`native_file_stream.dart`，零复制）；桌面用 `file_picker` 路径方案。

### 6.2 操作文档

入口：聊天 Tab（主界面第 3 项）；或 设置页 → 「局域网聊天」（`settings_screen.dart:134`，此时带返回键）。

#### 6.2.1 聊天首页（LanChatHomeScreen）— 3 个 Tab

1. **设备列表**：自动发现同网段在线设备。点设备 → 进入单聊页。离线残留设备可「确认删除」。
2. **聊天历史**：历史会话列表，未读角标；点击进入该单聊。
3. **聊天室**（`RoomListScreen`）：
   - **我的房间**：未建房显示「创建房间」（输入房间名，默认 `房间-你的昵称`）；已建房显示房间名/成员数，按钮「进入房间」、房主可「解散」、成员可「创建自己的房间」（先确认离开当前房）。
   - **附近房间**：发现设备中携带房间摘要的条目，点「加入」（已在别的房间会先确认离开；房主需先解散才能加入别的房间，`room_list_screen.dart:320-369`）。

**右上角操作**（`lan_chat_home_screen.dart:371-400`）：

- **ℹ️ 本机信息**：显示本机 IP、TCP 聊天端口、设备名；可「改昵称」（`_editNickname`，改后同步到发现服务，其它端立刻看到新名字）。
- **WiFi 图标**：开/关设备发现（关后设备列表与「附近房间」停止更新）。

> **发现端口非默认时**：进首页弹一次提醒（每天最多一次），可点「立即重置」恢复默认并重启发现（`lan_chat_home_screen.dart:42-89`）。

#### 6.2.2 单聊（ChatScreen）

从「设备列表」或「聊天历史」进入：

- **连接状态**（标题下方小字）：`正在连接中`（转圈）→ 成功 `已连接`（绿点）；失败显示 `等待对方连接中` 并每 4s 自动重试，对方上线即自动连上（`chat_screen.dart:139-179`）。
- **发文字**：输入框输入，回车/点发送按钮；未连接时发送会自动触发连接。
- **发文件**：
  - 输入框左侧 **⊕ 按钮** → 选文件发送（`_pickAndSendFile`）。移动端走原生选择器；桌面走 `file_picker`。
  - **桌面**：直接把文件**拖进聊天窗口**即发送（`chat_screen.dart:365-392`）。
  - 传输中顶部显示进度条文件卡，可**取消**（`chat_screen.dart:855-883`）。
- **右键/长按消息**（`MessageBubble`）：多选 → 「合并分享」（文字合并 + 文件附带真实路径）/「删除」（`chat_screen.dart:433-502`）。
- **右上角菜单**：查看详情（双方 IP/端口/ID）、打开接收文件夹、重新连接（未连上时出现，`chat_screen.dart:715-770`）。

> **注意**：Android 文件落地在系统「下载」目录；桌面/iOS 在 `zebra_received/`，点「打开接收文件夹」可直达。

#### 6.2.3 聊天室（RoomScreen）

从聊天室 Tab 点「进入房间」：

- 显示房间名、在线成员列表（点头像看成员详情，含 IP，可「发消息」进单聊）。
- 底部输入框发消息；**房主**可「解散房间」（二次确认，全员掉线）；**成员**可「离开」。
- 断线自动重连（最多 40 次 × 3s）；房主关闭 → 房群解散。

### 6.3 常见问题

| 症状 | 排查 |
|---|---|
| 设备列表为空 | 确认同网段；开 WiFi（右上角）；确认双方发现端口一致（默认 19422）；部分路由器会屏蔽广播/组播 |
| 聊天显示「等待对方连接中」 | 对方 App 未运行或离线；等对方启动 Zebra 后自动连上 |
| 文件收不到 | 看接收端是否显示传输进度；完成后去「下载」（Android）或 `zebra_received/`（桌面/iOS） |
| 端口被占用 | 聊天服务自动回退到候选端口；一般无需处理，心跳会广播真实端口 |
| 多网段/访客 WiFi | 同一二层广播域内才互通；AP 隔离（访客网）会导致发现失败 |

---

## 7. 设置、存储与数据管理

入口：设置 Tab（主界面第 5 项），页面 `settings_screen.dart`。

| 分组 | 项 | 说明 |
|---|---|---|
| 语言 | 语言 | 切换界面语言 |
| 主题 | 主题色 | 选种子色（圆形色板） |
| 主题 | 模式 | 浅色 / 深色 / 跟随系统 |
| 更多 | 日记 | 进入日记页（带返回键） |
| 更多 | 博客 | `RssExploreScreen(博客Tab)` |
| 更多 | 发现 | `RssExploreScreen(发现Tab)` |
| 更多 | 二维码 | `QrToolScreen`（生成/识别） |
| 局域网 | 局域网聊天 | 进入聊天首页（带返回键） |
| 局域网 | 发现端口 | 改 UDP 发现端口，留空恢复默认 19422，保存即重启发现服务 |
| 存储 | 存储信息 | 弹窗显示：系统信息（OS/核数/主机名）+ 各数据路径（缓存/数据库/文档/RSS），可「分享数据库」「清除运行数据」「清除全部数据」（`settings_screen.dart:536-626`） |
| 关于 | 检查更新 | 手动查新版本（`UpdateDialog`）；有新版提示可下载/跳过 |
| 关于 | 关于我们 | `AboutScreen`（含反馈、API 地址、唯一 ID） |
| 关于 | 唯一 ID | 点复制（`UniqueId.get()`，`settings_screen.dart:414-436`） |
| Linux 专属 | 从系统卸载 | 仅 Linux 显示，调 `zebra --uninstall`（`settings_screen.dart:176-182, 815-860`） |

**清除全部数据**（`_confirmClearAllData`）：删临时缓存 + 主数据库 + 应用支持目录，再重建空库并刷新各 Provider。

**自动更新**：启动时 `UpdateService` 检查；有更新弹窗可下载，「跳过」则 7 天内不再提示；「强制更新」不可跳过。

---

## 8. 其它工具（二维码 / 命令参考 / 发现）

| 功能 | 入口 | 说明 |
|---|---|---|
| 二维码工具 | SSH Tab 菜单「二维码」/ 设置页「二维码」 | 生成二维码（文本/链接）与相机/相册识别（`features/qr_tool/`） |
| Linux 命令参考 | 终端内（`LinuxCommandsScreen`） | 按分类浏览常用命令，支持搜索、分页加载，点击复制（`linux_commands_screen.dart`） |
| 发现 / 博客 | RSS 菜单「发现」、设置页「发现」「博客」 | `RssExploreScreen` 三 Tab：推荐 / 发现 / 博客 |
| 关于 / 反馈 | 设置 → 关于我们 | 版本信息、反馈入口（同邮箱 30 分钟内限一次） |

---

## 9. 数据与配置存储位置

统一根目录（`utils/zebra_paths.dart`）：`appDocumentsDir/zebra.dart.xin/`，下设子目录：

| 子目录 / 文件 | 内容 |
|---|---|
| `zebra_rss.db` | RSS 本地库（源 + 文章 + 备份） |
| `zebra.db` | 主库：连接（`connections`）、日记（`diary`）、聊天（`chat_messages` / `chat_peers`） |
| `rss/` | RSS 自动备份文件 |
| `diary/` | 日记 CSV 导出 |
| `ssh/` | 连接 CSV 导入导出 |
| `zebra_received/` | 局域网接收文件（桌面/iOS；Android 在系统「下载」） |

**SharedPreferences 键**（跨端配置）：

- 主题/语言：`theme_provider.dart` / `locale_provider.dart`
- 窗口尺寸/位置/最大化：`window_service.dart`
- RSS：`rss_sync_interval_minutes`、`rss_server_mode`、`rss_server_url`、`rss_server_sync_days`
- 局域网：`lan_chat_discovery_port`、`lan_chat_discovery_warning_date`、`lan_chat_user_name`、`lan_chat_device_id`（UUID）
- 更新：API 基址、跳过更新时间
- 阅读进度：`rss_scroll_<articleId>`

> **安全**：release 构建的主数据库启用 `PRAGMA key` 加密（`zebra_db_key_2016`，`database_service.dart:32-35`）；连接表含明文密码/私钥路径，导出 CSV 时请注意妥善保管。

---

*文档基于当前代码实现编写；功能演进请以代码与 `docs/` 下各专项设计文档（`RSS_DESIGN.md`、`LAN_CHAT_ROOM_DESIGN.md`、`API_SERVER.md` 等）为准。*
