# Zebra

跨平台客户端（Windows / macOS / Linux / Android / iOS / Web），集成五大功能块：

| 功能块 | 说明 | 代码位置 |
|---|---|---|
| SSH 终端 | 多标签远程终端、密码/密钥认证 | `lib/screens/terminal_screen.dart`、`lib/services/ssh_service.dart` |
| SFTP 文件管理 | 远端文件浏览/上传下载/编辑/压缩/进程清理 | `lib/screens/sftp_screen.dart`、`lib/services/sftp_service.dart` |
| RSS 阅读 | 本地订阅（OPML/定时同步）+ 服务器模式 | `lib/screens/rss/`、`lib/providers/rss_provider.dart` |
| 日记 | 本地日记，心情标记、搜索、CSV 导入导出 | `lib/screens/diary_screen.dart`、`lib/providers/diary_provider.dart` |
| 局域网聊天与文件传输 | UDP 发现 + TCP 单聊/聊天室 + 文件收发（免公网） | `lib/features/lan_chat/` |

## 文档

- **使用文档（完整功能说明与操作手册，区分 PC/移动端）**：[`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)
- 其它文档：
  - [`docs/APP_INTRO.md`](docs/APP_INTRO.md) — 应用简介
  - [`docs/CLIENT.md`](docs/CLIENT.md) — 客户端设计
  - [`docs/RSS_DESIGN.md`](docs/RSS_DESIGN.md) — RSS 设计
  - [`docs/LAN_CHAT_ROOM_DESIGN.md`](docs/LAN_CHAT_ROOM_DESIGN.md) — 局域网聊天室设计
  - [`docs/API_SERVER.md`](docs/API_SERVER.md) — 服务端 API
  - [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — 部署

## 构建

各平台构建脚本：

| 平台 | 脚本 |
|---|---|
| Android | `./build_android.sh` |
| iOS | `./build_ios.sh` |
| Linux | `./build_linux.sh` |
| macOS | `./build_mac.sh` |
| Windows | `build_windows.bat` |

Linux 安装到系统：`./linux_install.sh`；卸载（仅 Linux）：应用内「设置 → 从系统卸载」。

