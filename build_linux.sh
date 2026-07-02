#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

show_menu() {
    clear
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Build Tools (Linux)"
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
    rm -rf "$SCRIPT_DIR/linux/flutter/ephemeral"
    rm -rf "$SCRIPT_DIR/windows/flutter/ephemeral"
    rm -rf "$SCRIPT_DIR/.dart_tool"
    echo "Done!"
}

do_build() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Linux Build"
    echo "========================================"
    echo

    echo "[1/6] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/6] Building Flutter Linux release..."
    flutter build linux --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "[3/6] Building zebra-pack tool..."
    cd "$SCRIPT_DIR/packer"
    cargo build --release --bin zebra-pack
    if [ $? -ne 0 ]; then
        echo "[ERROR] Packer tool build failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi

    echo
    echo "[4/6] Packing files into data.bin..."
    target/release/zebra-pack -f ../build/linux/x64/release/bundle -e zebra -n zebra-ssh
    if [ $? -ne 0 ]; then
        echo "[ERROR] Packing failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi

    echo
    echo "[5/6] Building self-extracting exe..."
    cargo build --release --bin zebra
    if [ $? -ne 0 ]; then
        echo "[ERROR] Self-extracting exe build failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi
    cd "$SCRIPT_DIR"

    echo
    echo "[6/6] Creating desktop entry..."
    INSTALL_DIR="$HOME/.local"
    mkdir -p "$INSTALL_DIR/bin"
    mkdir -p "$INSTALL_DIR/share/icons"
    mkdir -p "$INSTALL_DIR/share/applications"

    cp packer/target/release/zebra "$INSTALL_DIR/bin/zebra"
    chmod +x "$INSTALL_DIR/bin/zebra"

    cp linux/icons/icon_512.png "$INSTALL_DIR/share/icons/zebra.png"

    cat > "$INSTALL_DIR/share/applications/zebra-ssh.desktop" << DESKTOP
[Desktop Entry]
Name=Zebra SSH
Comment=Zebra SSH Client
Exec=$INSTALL_DIR/bin/zebra
Icon=$INSTALL_DIR/share/icons/zebra.png
Terminal=false
Type=Application
Categories=Network;Utility;
DESKTOP

    echo
    echo "Done!"
    echo
    echo "Binary: $INSTALL_DIR/bin/zebra"
    echo "Desktop entry: $INSTALL_DIR/share/applications/zebra-ssh.desktop"
    echo
    echo "To install system-wide, run with sudo and use /usr/local instead of $HOME/.local"
}

# 兼容旧用法: ./build_linux.sh --clean 或 ./build_linux.sh
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
