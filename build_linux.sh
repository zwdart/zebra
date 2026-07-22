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
    echo "  [8] Exit"
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

# 交互式菜单
while true; do
    show_menu
    read -p "  Select option [1-8]: " choice

    case $choice in
        1) do_build ;;
        2) do_install ;;
        3) do_uninstall ;;
        4) do_clean ;;
        5) do_clean; do_build ;;
        6) do_run ;;
        7) do_pack ;;
        8) exit 0 ;;
        *) echo "Invalid option!" ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
