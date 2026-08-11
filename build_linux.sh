#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

show_menu() {
    clear
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Build Tools (Linux)"
    echo "========================================"
    echo ""
    echo "  [1] Build (full release)"
    echo "  [2] Install"
    echo "  [3] Uninstall"
    echo "  [4] Clean build artifacts"
    echo "  [5] Clean + Build"
    echo "  [6] Run"
    echo "  [7] Pack release zip"
    echo "  [8] Pack .deb package"
    echo "  [9] Quick Build & Run (flutter only)"
    echo "  [10] Exit"
    echo ""
}

do_clean() {
    echo ""
    echo "Cleaning build artifacts..."
    rm -rf "$SCRIPT_DIR/build"
    rm -rf "$SCRIPT_DIR/packer/target"
    rm -rf "$SCRIPT_DIR/linux/flutter/ephemeral"
    rm -rf "$SCRIPT_DIR/windows/flutter/ephemeral"
    rm -rf "$SCRIPT_DIR/.dart_tool"
    echo "Done!"
}

do_uninstall() {
    INSTALL_DIR="$HOME/.local"
    echo ""
    echo "Uninstalling Zebra SSH..."

    rm -f "$INSTALL_DIR/bin/zebra"
    rm -f "$INSTALL_DIR/share/icons/zebra.png"
    rm -f "$INSTALL_DIR/share/applications/xin.dart.zebra.desktop"
    rm -f "$INSTALL_DIR/share/applications/zebra-ssh.desktop"
    rm -rf "$INSTALL_DIR/share/zebra"

    update-desktop-database "$INSTALL_DIR/share/applications" 2>/dev/null
    gtk-update-icon-cache "$INSTALL_DIR/share/icons" 2>/dev/null

    echo "Done!"
}

do_build() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Linux Build"
    echo "========================================"
    echo

    echo "[1/5] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/5] Building Flutter Linux release..."
    cat > "$SCRIPT_DIR/lib/build_info.dart" << EOF
// Auto-generated build info - overwritten by build scripts
const String buildTime = '$BUILD_TIME';
EOF
    flutter build linux --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "[3/5] Building zebra-pack tool..."
    cd "$SCRIPT_DIR/packer"
    cargo build --release --bin zebra-pack
    if [ $? -ne 0 ]; then
        echo "[ERROR] Packer tool build failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi

    echo
    echo "[4/5] Packing files into data.bin..."
    target/release/zebra-pack -f ../build/linux/x64/release/bundle -e zebra -n zebra-ssh
    if [ $? -ne 0 ]; then
        echo "[ERROR] Packing failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi

    echo
    echo "[5/5] Building self-extracting exe..."
    cargo build --release --bin zebra
    if [ $? -ne 0 ]; then
        echo "[ERROR] Self-extracting exe build failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi
    cd "$SCRIPT_DIR"

    echo
    echo "Done! Binary: packer/target/release/zebra"
}

do_run() {
    cd "$SCRIPT_DIR"
    local binary="packer/target/release/zebra"

    if [ ! -f "$binary" ]; then
        echo "[ERROR] Binary not found. Run Build first."
        return 1
    fi

    echo ""
    echo "Launching Zebra SSH..."
    "$binary" &
}

do_install() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Install"
    echo "========================================"
    echo

    if [ ! -f packer/target/release/zebra ]; then
        echo "[ERROR] Binary not found. Run Build first."
        return 1
    fi

    INSTALL_DIR="$HOME/.local"
    mkdir -p "$INSTALL_DIR/bin"
    mkdir -p "$INSTALL_DIR/share/icons"
    mkdir -p "$INSTALL_DIR/share/applications"

    cp packer/target/release/zebra "$INSTALL_DIR/bin/zebra"
    chmod +x "$INSTALL_DIR/bin/zebra"

    cp linux/icons/icon_512.png "$INSTALL_DIR/share/icons/zebra.png"

    rm -f "$INSTALL_DIR/share/applications/zebra-ssh.desktop"

    cat > "$INSTALL_DIR/share/applications/xin.dart.zebra.desktop" << DESKTOP
[Desktop Entry]
Name=Zebra SSH
GenericName=SSH Client
Comment=Zebra SSH Client
Exec=$INSTALL_DIR/bin/zebra
Icon=$INSTALL_DIR/share/icons/zebra.png
Terminal=false
Type=Application
StartupWMClass=xin.dart.zebra
Categories=Network;Utility;
DESKTOP

    update-desktop-database "$INSTALL_DIR/share/applications" 2>/dev/null
    gtk-update-icon-cache "$INSTALL_DIR/share/icons" 2>/dev/null

    echo
    echo "Done!"
    echo "Binary: $INSTALL_DIR/bin/zebra"
    echo "Desktop entry: $INSTALL_DIR/share/applications/xin.dart.zebra.desktop"
}

do_quick_build_run() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Quick Build & Run"
    echo "========================================"
    echo

    echo "[1/2] Building Flutter Linux release..."
    cat > "$SCRIPT_DIR/lib/build_info.dart" << EOF
// Auto-generated build info - overwritten by build scripts
const String buildTime = '$BUILD_TIME';
EOF
    flutter build linux --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    local binary="build/linux/x64/release/bundle/zebra"
    if [ ! -f "$binary" ]; then
        echo "[ERROR] Binary not found: $binary"
        return 1
    fi

    echo
    echo "[2/2] Launching Zebra SSH..."
    "$binary" &
    echo "Done! PID: $!"
}

do_pack() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Pack Release Zip"
    echo "========================================"
    echo

    local binary="packer/target/release/zebra"
    local install_script="linux_install.sh"
    local release_dir="packer/target/release"

    if [ ! -f "$binary" ]; then
        echo "[ERROR] Binary not found: $binary"
        echo "  Please run Build first."
        return 1
    fi

    if [ ! -f "$install_script" ]; then
        echo "[ERROR] Install script not found: $install_script"
        return 1
    fi

    local timestamp=$(date +"%Y%m%d%H%M")
    local zip_name="linux_zebra_${timestamp}.zip"
    local zip_path="$release_dir/$zip_name"

    echo "  Binary:       $binary"
    echo "  Install:      $install_script"
    echo "  Output:       $zip_path"
    echo

    cd "$release_dir"
    zip -j "$zip_name" "$SCRIPT_DIR/$install_script" "$(pwd)/zebra"

    if [ $? -ne 0 ]; then
        echo "[ERROR] Zip failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi

    cd "$SCRIPT_DIR"
    echo
    echo "Done! Output: $zip_path"
}

do_pack_deb() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Pack .deb Package"
    echo "========================================"
    echo

    local bundle="build/linux/x64/release/bundle"
    if [ ! -f "$bundle/zebra" ]; then
        echo "[ERROR] Bundle not found: $bundle"
        echo "  Please run Build first."
        return 1
    fi

    if ! command -v dpkg-deb >/dev/null 2>&1; then
        echo "[ERROR] dpkg-deb not found. Install with: sudo apt install dpkg-dev"
        return 1
    fi

    local version
    version=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
    [ -z "$version" ] && version="1.0.0"

    # 打包根目录与最终 .deb 都输出到 packer/runtimes(runtime 数据目录,已 gitignore)
    local out_dir="packer/runtimes"
    local root="$out_dir/zebra-deb"
    rm -rf "$root"
    mkdir -p "$root/DEBIAN" "$root/usr/bin" "$root/usr/share/applications" \
             "$root/usr/share/icons/hicolor" "$root/opt/zebra"
    cp -r "$bundle/." "$root/opt/zebra/"
    ln -s /opt/zebra/zebra "$root/usr/bin/zebra"

    # 多尺寸 hicolor 图标(尺寸与目录匹配),桌面环境按需选择
    for size in 16 24 32 48 64 128 256 512; do
        if [ -f "linux/icons/icon_${size}.png" ]; then
            mkdir -p "$root/usr/share/icons/hicolor/${size}x${size}/apps"
            cp "linux/icons/icon_${size}.png" "$root/usr/share/icons/hicolor/${size}x${size}/apps/zebra.png"
        fi
    done

    cat > "$root/usr/share/applications/zebra.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Zebra
Comment=Zebra Desktop App
Exec=/opt/zebra/zebra
Icon=zebra
# WM_CLASS 是 xin.dart.zebra(linux/runner/my_application.cc 里 g_set_prgname(APPLICATION_ID)),
# 不加 StartupWMClass 则 GNOME 常驻台无法把窗口匹配到本 .desktop,显示默认齿轮图标
StartupWMClass=xin.dart.zebra
Terminal=false
Categories=Network;Utility;
EOF

    cat > "$root/DEBIAN/control" << EOF
Package: zebra
Version: $version
Section: net
Priority: optional
Architecture: amd64
Maintainer: Zebra <zebra@dart.xin>
Installed-Size: $(du -sk "$root/opt" | awk '{print $1}')
Description: Zebra desktop application
EOF

    # postinst:安装/升级后刷新图标缓存与桌面数据库,否则新装的图标不显示
    cat > "$root/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
exit 0
EOF
    chmod +x "$root/DEBIAN/postinst"

    local deb_name="$out_dir/zebra_${version}_amd64.deb"
    dpkg-deb --build --root-owner-group "$root" "$deb_name"
    if [ $? -ne 0 ]; then
        echo "[ERROR] dpkg-deb failed!"
        return 1
    fi

    echo
    echo "Done! Package: $SCRIPT_DIR/$deb_name"
}

# 兼容旧用法: ./build_linux.sh --clean 或 ./build_linux.sh
if [ "$1" = "--clean" ]; then
    do_clean
    do_build
    exit 0
fi

if [ "$1" = "--run" ]; then
    do_run
    exit 0
fi

if [ "$1" = "--pack" ]; then
    do_pack
    exit 0
fi

if [ "$1" = "--quick" ]; then
    do_quick_build_run
    exit 0
fi

if [ "$1" = "--deb" ]; then
    do_pack_deb
    exit 0
fi

# 交互式菜单
while true; do
    show_menu
    read -p "  Select option [1-10]: " choice

    case $choice in
        1) do_build ;;
        2) do_install ;;
        3) do_uninstall ;;
        4) do_clean ;;
        5) do_clean; do_build ;;
        6) do_run ;;
        7) do_pack ;;
        8) do_pack_deb ;;
        9) do_quick_build_run ;;
        10) exit 0 ;;
        *) echo "Invalid option!" ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
