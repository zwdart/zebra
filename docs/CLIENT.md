# Zebra SSH 客户端

Flutter 跨平台 SSH 客户端，支持终端、SFTP、系统监控等功能。

## 技术栈

- **框架**: Flutter (Dart SDK ^3.11.4)
- **状态管理**: Provider
- **SSH**: dartssh2
- **终端**: xterm
- **数据库**: sqlite3 + sqlite3_flutter_libs
- **平台**: Android / iOS / Windows / macOS / Linux / Web

## 项目结构

```
lib/
├── main.dart              # 应用入口
├── build_info.dart        # 构建信息
├── database/
│   └── database_service.dart    # SQLite 数据库
├── models/
│   ├── ssh_connection.dart      # SSH 连接模型
│   ├── terminal_session.dart    # 终端会话模型
│   ├── sftp_file_item.dart      # SFTP 文件模型
│   ├── blog_post.dart           # 博客模型
│   ├── diary_entry.dart         # 日记模型
│   ├── discovery_item.dart      # 发现内容模型
│   ├── feedback_item.dart       # 反馈模型
│   └── linux_command.dart       # Linux 命令模型
├── providers/
│   ├── connection_provider.dart # 连接管理
│   ├── ssh_provider.dart        # SSH 状态
│   ├── sftp_provider.dart       # SFTP 状态
│   ├── theme_provider.dart      # 主题切换
│   ├── locale_provider.dart     # 国际化
│   ├── monitor_provider.dart    # 系统监控
│   ├── process_provider.dart    # 进程管理
│   ├── cleanup_provider.dart    # 磁盘清理
│   ├── update_provider.dart     # 更新检查
│   └── linux_command_provider.dart # 命令管理
├── services/
│   ├── ssh_service.dart         # SSH 核心服务
│   ├── sftp_service.dart        # SFTP 服务
│   ├── update_service.dart      # 更新服务
│   ├── blog_service.dart        # 博客服务
│   ├── discovery_service.dart   # 发现服务
│   ├── feedback_service.dart    # 反馈服务
│   ├── compression_service.dart # 压缩服务
│   └── window_service.dart      # 窗口管理
├── screens/                     # 页面
│   ├── home_screen.dart         # 首页 (连接列表)
│   ├── terminal_screen.dart     # 终端
│   ├── sftp_screen.dart         # SFTP 文件管理
│   ├── monitor_screen.dart      # 系统监控
│   ├── process_screen.dart      # 进程管理
│   ├── cleanup_screen.dart      # 磁盘清理
│   ├── connection_form_screen.dart # 连接编辑
│   ├── settings_screen.dart     # 设置
│   ├── diary_screen.dart        # 日记
│   ├── blog_screen.dart         # 博客
│   ├── discovery_screen.dart    # 发现
│   ├── feedback_screen.dart     # 反馈
│   ├── about_screen.dart        # 关于
│   ├── update_dialog.dart       # 更新弹窗
│   └── linux_commands_screen.dart # 常用命令
├── widgets/                     # 通用组件
├── theme/                       # 主题配置
├── l10n/                        # 国际化资源
└── utils/                       # 工具函数
```

## 数据库

本地 SQLite 数据库，路径: `{app_support_dir}/zebra/zebra.db`

### connections - SSH 连接

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

### diary - 日记

| 列名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| id | INTEGER | 自增 | 主键 |
| title | TEXT | '' | 标题 |
| content | TEXT | '' | 内容 |
| mood | TEXT | 'neutral' | 心情: happy/neutral/sad/angry/excited |
| created_at | TEXT | - | 创建时间 (ISO 8601) |
| updated_at | TEXT | - | 更新时间 (ISO 8601) |

## 核心模块

### SSH 服务 (`ssh_service.dart`)

- 支持密码和密钥两种认证方式
- 多终端会话 (每个终端独立 PTY)
- 终端窗口大小动态调整
- 远程命令执行

```dart
// 连接
await sshService.connect(
  host: '192.168.1.100',
  port: 22,
  username: 'root',
  password: 'xxx',
);

// 打开终端
final terminal = await sshService.openTerminal(cols: 120, rows: 40);

// 执行命令
final output = await sshService.execute('ls -la');
```

### SFTP 服务

- 浏览远程目录
- 文件上传/下载
- 支持桌面拖拽上传

### 更新服务

- 启动时静默检查更新
- 支持强制更新
- 跳过更新 (7 天有效)
- 调用后端 `/api/version` 接口

### 系统监控

- CPU / 内存 / 磁盘使用率
- 进程列表查看和管理
- 磁盘清理建议

## 页面功能

| 页面 | 功能 |
|------|------|
| HomeScreen | 连接列表、搜索、新增/编辑/删除 |
| TerminalScreen | SSH 终端 (多标签) |
| SftpScreen | 文件管理、上传下载 |
| MonitorScreen | 系统资源监控 |
| ProcessScreen | 进程查看/终止 |
| CleanupScreen | 磁盘清理 |
| ConnectionFormScreen | 连接编辑表单 |
| SettingsScreen | 主题、语言、更新设置 |
| DiaryScreen | 本地日记 |
| BlogScreen | 在线博客 |
| DiscoveryScreen | 推荐内容 |
| FeedbackScreen | 提交反馈 |
| AboutScreen | 关于信息 |
| UpdateDialog | 更新提示弹窗 |
| LinuxCommandsScreen | 常用 Linux 命令参考 |

## 构建

各平台构建命令和打包流程详见 [DEPLOYMENT.md](DEPLOYMENT.md)。

快速构建:

```bash
# Android
./build_android.sh

# iOS
./build_ios.sh

# Windows
build_windows.bat

# macOS
./build_mac.sh

# Linux
./build_linux.sh
```

## 异常处理

### SSH 连接异常

| 异常 | 处理方式 |
|------|----------|
| `Cannot connect to host:port` | 连接超时或网络不可达，提示检查网络 |
| `Authentication failed` | 密码/密钥错误，提示重新输入 |
| `Connection closed` | 服务端主动断开，终端显示关闭提示 |
| `Private key file not found` | 密钥文件路径无效，提示检查配置 |

### SFTP 异常

- 文件操作失败: 显示具体错误 (权限不足、文件不存在等)
- 上传/下载中断: 保留已传输部分，允许重试

### 更新异常

- 网络请求失败: 静默跳过，不影响正常使用
- 下载失败: 提示重试，不自动重试

### 反馈提交异常

- 限流: 同一邮箱 30 分钟内只能提交一次
- 网络错误: 显示具体错误信息 (无法连接/超时/服务器异常)

## 依赖说明

| 包 | 用途 |
|---|------|
| dartssh2 | SSH 协议实现 |
| xterm | 终端渲染 |
| sqlite3 | 本地数据库 |
| provider | 状态管理 |
| file_picker | 文件选择 |
| desktop_drop | 拖拽上传 |
| share_plus | 分享功能 |
| window_manager | 桌面窗口控制 |
| http | HTTP 请求 |
| package_info_plus | 应用信息 |
| shared_preferences | 本地配置持久化 |
| path_provider | 应用目录路径 |
| url_launcher | 打开外部链接 |
| flutter_html | HTML 渲染 |
| markdown | Markdown 渲染 |
| archive | 文件压缩/解压 |

## 国际化

支持中文和英文，通过 `l10n/` 目录管理翻译资源。使用 `AppLocalizations` 类访问本地化字符串。

## 主题

支持亮色/暗色主题切换，通过 `ThemeProvider` 管理。桌面端使用自定义标题栏。
