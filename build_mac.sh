#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

show_menu() {
    clear
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Build Tools (macOS)"
    echo "========================================"
    echo ""
    echo "  [1] Build (full release)"
    echo "  [2] Clean build artifacts"
    echo "  [3] Clean + Build"
    echo "  [4] Exit"
    echo ""
}

do_clean() {
    echo ""
    echo "Cleaning build artifacts..."
    rm -rf "$SCRIPT_DIR/build"
    rm -rf "$SCRIPT_DIR/packer/target"
    rm -rf "$SCRIPT_DIR/macos/flutter/ephemeral"
    rm -rf "$SCRIPT_DIR/.dart_tool"
    echo "Done!"
}

do_build() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - macOS Build"
    echo "========================================"
    echo

    echo "[1/4] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/4] Building Flutter macOS release..."
    cat > "$SCRIPT_DIR/lib/build_info.dart" << EOF
// Auto-generated build info - overwritten by build scripts
const String buildTime = '$BUILD_TIME';
EOF
    flutter build macos --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "[3/4] Preparing Zebra.app (real .app bundle)..."
    # 真实 .app 方案:直接使用 Flutter 构建产物,不经 zebra-pack 自解压壳,
    # 保证 Dock 图标/代码签名/Gatekeeper/商店行为全部正常。
    # 产物 bundle 名取决于 Xcode 工程的 PRODUCT_NAME(本项目 AppInfo.xcconfig
    # 设为 zebra,故产物为 zebra.app),不硬编码,直接动态查找第一个 .app
    APP_BUNDLE="$(find "$SCRIPT_DIR/build/macos/Build/Products/Release" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -1)"
    if [ -z "$APP_BUNDLE" ]; then
        APP_BUNDLE="$(find "$SCRIPT_DIR/build/macos" -maxdepth 6 -name '*.app' -type d 2>/dev/null | head -1)"
    fi
    if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
        echo "[ERROR] macOS app bundle not found under build/macos"
        find "$SCRIPT_DIR/build/macos" -maxdepth 6 2>/dev/null || echo "(build/macos does not exist)"
        return 1
    fi
    echo "  Using app bundle: $APP_BUNDLE"
    EXE_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_BUNDLE/Contents/Info.plist")"
    echo "  Bundle executable: $EXE_NAME"
    ZEBRA_APP="$SCRIPT_DIR/build/macos/Zebra.app"
    rm -rf "$ZEBRA_APP"
    cp -R "$APP_BUNDLE" "$ZEBRA_APP"
    # 应用显示名与旧版自解压壳一致(真实产物 CFBundleName 为 zebra)
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Zebra SSH" "$ZEBRA_APP/Contents/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Zebra SSH" "$ZEBRA_APP/Contents/Info.plist"
    # PlistBuddy 修改 Info.plist 会破坏 Flutter 构建时的 ad-hoc 签名;
    # 必须重新签名,否则带沙盒 entitlement 的应用启动即崩
    # (EXC_BAD_INSTRUCTION,dyld secinit 校验签名失败,OSStatus -67030)
    codesign --force --deep --sign - --entitlements "$SCRIPT_DIR/macos/Runner/Release.entitlements" "$ZEBRA_APP"
    codesign --verify --deep --strict "$ZEBRA_APP"

    echo
    echo "[4/4] Done!"
    echo
    echo "Output: $ZEBRA_APP"
    ls -lh "$ZEBRA_APP/Contents/MacOS/$EXE_NAME"
}

# 兼容旧用法: ./build_mac.sh --clean 或 ./build_mac.sh
if [ "$1" = "--clean" ]; then
    do_clean
    do_build
    exit 0
fi

# 交互式菜单
while true; do
    show_menu
    read -p "  Select option [1-4]: " choice

    case $choice in
        1) do_build ;;
        2) do_clean ;;
        3) do_clean; do_build ;;
        4) exit 0 ;;
        *) echo "Invalid option!" ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
