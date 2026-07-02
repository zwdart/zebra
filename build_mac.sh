#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

    echo "[1/7] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/7] Building Flutter macOS release..."
    flutter build macos --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "[3/7] Building zebra-pack tool..."
    cd "$SCRIPT_DIR/packer"
    cargo build --release --bin zebra-pack
    if [ $? -ne 0 ]; then
        echo "[ERROR] Packer tool build failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi

    echo
    echo "[4/7] Packing files into data.bin..."
    APP_DIR="$SCRIPT_DIR/build/macos/Build/Products/Release/Runner.app"
    EXE_PATH="Contents/MacOS/Runner"
    target/release/zebra-pack -f "$APP_DIR" -e "$EXE_PATH" -n zebra-ssh
    if [ $? -ne 0 ]; then
        echo "[ERROR] Packing failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi

    echo
    echo "[5/7] Building self-extracting exe..."
    cargo build --release --bin zebra
    if [ $? -ne 0 ]; then
        echo "[ERROR] Self-extracting exe build failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi
    cd "$SCRIPT_DIR"

    echo
    echo "[6/7] Creating .app bundle..."
    APP_BUNDLE="packer/target/release/Zebra.app"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    cp packer/target/release/zebra "$APP_BUNDLE/Contents/MacOS/zebra"
    chmod +x "$APP_BUNDLE/Contents/MacOS/zebra"

    # Generate .iconset from PNGs and convert to .icns
    ICONSET="packer/macos_iconset"
    ICON_SRC="macos/Runner/Assets.xcassets/AppIcon.appiconset"
    if [ -d "$ICONSET" ]; then
        iconutil -c icns "$ICONSET" --output "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    else
        echo "  [WARN] macos_iconset not found, generating from app icons..."
        ICONSET="$APP_BUNDLE/Contents/Resources/AppIcon.iconset"
        mkdir -p "$ICONSET"
        sips -z 16 16     "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_16x16.png"        2>/dev/null
        sips -z 32 32     "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_16x16@2x.png"     2>/dev/null
        sips -z 32 32     "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_32x32.png"        2>/dev/null
        sips -z 64 64     "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_32x32@2x.png"     2>/dev/null
        sips -z 128 128   "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_128x128.png"      2>/dev/null
        sips -z 256 256   "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_128x128@2x.png"   2>/dev/null
        sips -z 256 256   "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_256x256.png"      2>/dev/null
        sips -z 512 512   "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_256x256@2x.png"   2>/dev/null
        sips -z 512 512   "$ICON_SRC/app_icon_1024.png" --out "$ICONSET/icon_512x512.png"      2>/dev/null
        cp "$ICON_SRC/app_icon_1024.png" "$ICONSET/icon_512x512@2x.png"
        iconutil -c icns "$ICONSET" --output "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        rm -rf "$ICONSET"
    fi

    cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Zebra</string>
    <key>CFBundleDisplayName</key>
    <string>Zebra SSH</string>
    <key>CFBundleIdentifier</key>
    <string>com.zebra.ssh</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>zebra</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

    echo
    echo "[7/7] Done!"
    echo
    echo "Output: $APP_BUNDLE"
    ls -lh "$APP_BUNDLE/Contents/MacOS/zebra"
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
