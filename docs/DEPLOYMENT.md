# Zebra 部署与 CI/CD 说明

## 目录结构

```
zebra/
├── build_android.sh        # Android 构建脚本
├── build_ios.sh            # iOS 构建脚本
├── build_linux.sh          # Linux 构建脚本
├── build_mac.sh            # macOS 构建脚本
├── build_windows.bat       # Windows 构建脚本
├── packer/                 # Rust 打包工具 + API 服务
│   ├── Makefile            # icon-gen 构建
│   ├── zebra-api.sh        # API 服务管理脚本
│   ├── zebra-api.service   # Systemd 服务配置
│   ├── zebra-api.conf      # Nginx 配置
│   └── config.toml         # API 服务配置
├── lib/
│   ├── build_info.dart     # 构建时间 (自动生成，已加入 .gitignore)
│   └── ...                 # 其余应用代码
```

## 环境依赖

### 后端 (zebra-api)

| 依赖 | 版本 | 用途 |
|------|------|------|
| Rust | >= 1.75 | 编译 API 服务 |
| cargo | - | Rust 包管理 |
| musl-tools | - | Linux 静态编译 (可选) |

### 客户端 (Flutter)

| 依赖 | 版本 | 用途 |
|------|------|------|
| Flutter | >= 3.11 | 跨平台 UI |
| Dart | >= 3.11.4 | Flutter SDK |
| Android SDK | - | Android 构建 |
| Xcode | >= 14 | iOS/macOS 构建 |
| CocoaPods | - | iOS 依赖管理 |

## 后端部署

### 编译 API 服务

```bash
cd packer

# 方式 1: 使用管理脚本 (推荐)
./zebra-api.sh build

# 方式 2: 直接编译 (Linux 静态编译)
cargo build --release --features api-server --bin zebra-api --target x86_64-unknown-linux-musl

# 方式 3: 直接编译 (当前平台)
cargo build --release --features api-server --bin zebra-api
```

编译产物: `packer/target/release/zebra-api`

### 服务管理

```bash
# 使用管理脚本
./zebra-api.sh run              # 启动
./zebra-api.sh run --port 8080  # 指定端口启动
./zebra-api.sh stop             # 停止
./zebra-api.sh restart          # 重启
./zebra-api.sh status           # 查看状态
./zebra-api.sh logs             # 查看日志
```

### Systemd 部署 (生产环境)

```bash
# 1. 编译
cd packer && ./zebra-api.sh build

# 2. 安装到 /opt/zebraapi
sudo mkdir -p /opt/zebraapi
sudo cp target/release/zebra-api /opt/zebraapi/
sudo cp config.toml /opt/zebraapi/
sudo cp -r static /opt/zebraapi/

# 3. 安装 systemd 服务
sudo cp zebra-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable zebra-api
sudo systemctl start zebra-api

# 4. 查看状态
sudo systemctl status zebra-api
sudo journalctl -u zebra-api -f
```

### Nginx 反向代理

```bash
# 1. 安装 Nginx
sudo apt install nginx

# 2. 复制配置
sudo cp zebra-api.conf /etc/nginx/sites-available/zebra-api
sudo ln -sf /etc/nginx/sites-available/zebra-api /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 3. 配置 SSL 证书
sudo mkdir -p /etc/nginx/ssl
# 将证书文件放到 /etc/nginx/ssl/ 目录

# 4. 重载 Nginx
sudo nginx -t
sudo systemctl reload nginx
```

### 目录结构

部署后服务器目录:

```
/opt/zebraapi/
├── zebra-api              # 可执行文件
├── config.toml            # 配置文件
├── static/                # 管理后台 HTML
│   ├── admin.html
│   ├── blog.html
│   ├── post.html
│   └── stats.html
└── runtimes/              # 数据目录 (自动创建)
    ├── versions.db        # SQLite 数据库
    ├── uploads/           # 上传文件
    └── logs/              # 日志
        └── api-YYYY-MM-DD.log
```

## 客户端构建

### Android

```bash
# 交互式菜单
./build_android.sh

# 直接构建 APK
./build_android.sh --clean

# 或手动构建
flutter pub get
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk

# 分 ABI 构建
flutter build apk --split-per-abi --release

# 构建 App Bundle (上架应用商店)
flutter build appbundle --release
```

### iOS

```bash
# 交互式菜单
./build_ios.sh

# 构建 iOS (未签名)
./build_ios.sh --clean

# 或手动构建
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter build ios --release --no-codesign

# 构建 IPA (分发)
flutter build ipa --release
```

### macOS

```bash
# 交互式菜单
./build_mac.sh

# 直接构建
./build_mac.sh --clean

# 或手动构建
flutter pub get
flutter build macos --release
# 然后使用 packer 打包成 .app
```

### Linux

```bash
# 交互式菜单
./build_linux.sh

# 直接构建
./build_linux.sh --clean

# 或手动构建
flutter pub get
flutter build linux --release
# 然后使用 packer 打包
```

### Windows

```batch
REM 交互式菜单
build_windows.bat

REM 或手动构建
flutter pub get
flutter build windows --release
REM 然后使用 packer 打包
```

## 打包流程 (桌面端)

桌面端使用 packer 工具将 Flutter 产物打包成自解压可执行文件:

```
Flutter 产物 → zebra-pack (打包) → data.bin → zebra (自解压可执行文件)
```

```bash
cd packer

# 1. 编译打包工具
cargo build --release --bin zebra-pack

# 2. 打包 Flutter 产物
# Linux:
target/release/zebra-pack -f ../build/linux/x64/release/bundle -e zebra -n zebra-ssh

# macOS:
target/release/zebra-pack -f ../build/macos/Build/Products/Release/Runner.app -e Contents/MacOS/Runner -n zebra-ssh

# Windows:
target\release\zebra-pack.exe -f ..\build\windows\x64\runner\Release -e zebra.exe -n zebra-ssh

# 3. 编译自解压可执行文件
cargo build --release --bin zebra
# 产物: target/release/zebra (或 zebra.exe)
```

## CI/CD

项目当前无预置 CI/CD 配置。以下是推荐的 GitHub Actions 方案。

### GitHub Actions - 后端部署

创建 `.github/workflows/deploy-api.yml`:

```yaml
name: Deploy API Server

on:
  push:
    branches: [main]
    paths: ['packer/**']
  workflow_dispatch:

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: x86_64-unknown-linux-musl

      - name: Install musl-tools
        run: sudo apt-get update && sudo apt-get install -y musl-tools

      - name: Build API Server
        working-directory: packer
        run: cargo build --release --features api-server --bin zebra-api --target x86_64-unknown-linux-musl

      - name: Deploy to server
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          source: "packer/target/x86_64-unknown-linux-musl/release/zebra-api"
          target: "/opt/zebraapi/"
          strip_components: 4

      - name: Restart service
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          script: |
            sudo systemctl restart zebra-api
            sudo systemctl status zebra-api --no-pager
```

### GitHub Actions - 客户端构建

创建 `.github/workflows/build-clients.yml`:

```yaml
name: Build Clients

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      platform:
        description: 'Target platform'
        required: true
        default: 'all'
        type: choice
        options:
          - all
          - android
          - ios
          - linux
          - macos
          - windows

jobs:
  build-android:
    if: ${{ github.event.inputs.platform == 'all' || github.event.inputs.platform == 'android' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: 'stable'

      - name: Build APK
        run: |
          flutter pub get
          flutter build apk --release

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: zebra-android
          path: build/app/outputs/flutter-apk/app-release.apk

  build-linux:
    if: ${{ github.event.inputs.platform == 'all' || github.event.inputs.platform == 'linux' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: 'stable'

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Build Linux
        run: |
          flutter pub get
          flutter build linux --release
          cd packer
          cargo build --release --bin zebra-pack
          cargo build --release --bin zebra

      - name: Upload Binary
        uses: actions/upload-artifact@v4
        with:
          name: zebra-linux
          path: packer/target/release/zebra

  build-windows:
    if: ${{ github.event.inputs.platform == 'all' || github.event.inputs.platform == 'windows' }}
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: 'stable'

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Build Windows
        run: |
          flutter pub get
          flutter build windows --release
          cd packer
          cargo build --release --bin zebra-pack
          cargo build --release --bin zebra

      - name: Upload Binary
        uses: actions/upload-artifact@v4
        with:
          name: zebra-windows
          path: packer/target/release/zebra.exe

  build-macos:
    if: ${{ github.event.inputs.platform == 'all' || github.event.inputs.platform == 'macos' }}
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: 'stable'

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Build macOS
        run: |
          flutter pub get
          flutter build macos --release
          cd packer
          cargo build --release --bin zebra-pack
          cargo build --release --bin zebra

      - name: Upload App
        uses: actions/upload-artifact@v4
        with:
          name: zebra-macos
          path: packer/target/release/Zebra.app
```

### 发布流程

1. **更新版本号**: 修改 `pubspec.yaml` 中的 `version`
2. **推送代码**: `git push origin main`
3. **创建 Tag**: `git tag v1.x.x && git push origin v1.x.x`
4. **触发构建**: Tag 推送自动触发 CI 构建
5. **下载产物**: 从 GitHub Actions Artifacts 下载各平台产物
6. **上传到服务器**: 通过管理后台上传版本文件
7. **通知用户**: 应用启动时自动检查更新

### 需要配置的 Secrets

在 GitHub 仓库 Settings → Secrets → Actions 中添加:

| Secret | 说明 |
|--------|------|
| `SERVER_HOST` | 服务器 IP 或域名 |
| `SERVER_USER` | SSH 登录用户名 |
| `SERVER_SSH_KEY` | SSH 私钥 |

## 版本发布检查清单

- [ ] 更新 `pubspec.yaml` 版本号
- [ ] 更新 `packer/Cargo.toml` 版本号 (如适用)
- [ ] 测试各平台构建
- [ ] 测试 API 服务启动
- [ ] 测试客户端更新检查
- [ ] 创建 Git Tag
- [ ] 等待 CI 构建完成
- [ ] 上传版本文件到管理后台
- [ ] 验证更新检查接口返回正确
- [ ] 通知用户更新

## 常见问题

### 编译错误

**Rust 编译失败**: 检查 Rust 版本 >= 1.75，运行 `rustup update`

**Flutter 编译失败**: 检查 Flutter 版本 >= 3.11，运行 `flutter upgrade`

**musl 编译失败**: 安装 musl-tools: `sudo apt install musl-tools`

### 部署问题

**服务启动失败**: 检查端口占用 `lsof -i:8686`，查看日志 `journalctl -u zebra-api`

**Nginx 502**: 确认 API 服务已启动，检查 Nginx 配置 `sudo nginx -t`

**数据库错误**: 检查 `runtimes/` 目录权限，确认 SQLite 已安装

### 构建问题

**Android SDK 找不到**: 设置 `ANDROID_HOME` 环境变量

**iOS 签名失败**: 在 Xcode 中配置签名证书

**打包工具编译失败**: 确认已安装 Rust 工具链
