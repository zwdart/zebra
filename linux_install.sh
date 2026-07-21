#!/bin/bash
# ============================================================
#  Zebra SSH - Standalone Installer (Linux)
#  用法: ./linux_install.sh [选项] [可执行文件路径]
#
#  默认从当前目录加载 zebra 可执行文件。
#  图标已嵌入在可执行文件中，安装时自动提取。
# ============================================================

set -e

APP_NAME="zebra"
APP_DISPLAY="Zebra SSH"
APP_DESKTOP="xin.dart.zebra.desktop"
APP_COMMENT="SSH Client"
APP_CATEGORIES="Network;Utility;"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- 路径解析 ---

get_install_dirs() {
    local base="${XDG_DATA_HOME:-$HOME/.local}"
    INSTALL_BIN="$base/bin"
    INSTALL_ICON="$base/share/icons"
    INSTALL_DESKTOP="$base/share/applications"
}

# --- 颜色输出 ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 核心函数 ---

extract_icon_from_binary() {
    local binary="$1"
    local output="$2"

    if ! file "$binary" | grep -q "ELF"; then
        return 1
    fi

    # 使用 Python 提取嵌入的 PNG
    if command -v python3 &>/dev/null; then
        python3 -c "
import sys
data = open(sys.argv[1], 'rb').read()
png_header = b'\x89PNG\r\n\x1a\n'
png_footer = b'IEND\xaeB\x60\x82'
offset = data.find(png_header)
if offset < 0:
    sys.exit(1)
end = data.find(png_footer, offset)
if end < 0:
    sys.exit(1)
with open(sys.argv[2], 'wb') as f:
    f.write(data[offset:end+12])
" "$binary" "$output" 2>/dev/null
    else
        local offset
        offset=$(LC_ALL=C grep -aoP '\x89PNG\r\n\x1a\n' "$binary" | head -1 | grep -ob '\x89' | head -1 | cut -d: -f1) 2>/dev/null
        [ -z "$offset" ] && return 1
        local end_pattern
        end_pattern=$(LC_ALL=C grep -aoP 'IEND\xaeB\x60\x82' "$binary" | head -1 | grep -ob 'I' | head -1 | cut -d: -f1) 2>/dev/null
        [ -z "$end_pattern" ] && return 1
        local length=$((end_pattern - offset + 12))
        dd if="$binary" bs=1 skip="$offset" count="$length" of="$output" 2>/dev/null
    fi

    if file "$output" | grep -q "PNG"; then
        return 0
    else
        rm -f "$output"
        return 1
    fi
}

do_install() {
    local binary_path="$1"

    echo ""
    echo "========================================"
    echo "  $APP_DISPLAY - Install"
    echo "========================================"
    echo

    # 确定可执行文件：默认当前目录下的 zebra
    if [ -n "$binary_path" ]; then
        BINARY="$binary_path"
    else
        BINARY="$SCRIPT_DIR/$APP_NAME"
    fi

    if [ ! -f "$BINARY" ]; then
        error "Binary not found: $BINARY"
        echo "  Usage: $0 [BINARY_PATH]"
        exit 1
    fi

    info "Using binary: $BINARY"

    get_install_dirs

    # 创建目录
    mkdir -p "$INSTALL_BIN"
    mkdir -p "$INSTALL_ICON"
    mkdir -p "$INSTALL_DESKTOP"

    # 复制可执行文件（跳过源和目标相同的情况）
    info "Installing binary..."
    local real_target
    real_target=$(realpath "$INSTALL_BIN/$APP_NAME" 2>/dev/null || echo "")
    if [ -z "$real_target" ] || [ "$(realpath "$BINARY")" != "$real_target" ]; then
        cp "$BINARY" "$INSTALL_BIN/$APP_NAME"
    fi
    chmod +x "$INSTALL_BIN/$APP_NAME"

    # 提取/安装图标
    info "Extracting icon from binary..."
    if extract_icon_from_binary "$BINARY" "$INSTALL_ICON/zebra.png"; then
        info "Icon extracted successfully."
    else
        warn "Could not extract icon from binary."
        local src_icon="$SCRIPT_DIR/linux/icons/icon_512.png"
        if [ -f "$src_icon" ]; then
            cp "$src_icon" "$INSTALL_ICON/zebra.png"
            info "Icon copied from source."
        else
            warn "No icon available. Desktop entry may show default icon."
        fi
    fi

    # 清理旧的 desktop 文件
    rm -f "$INSTALL_DESKTOP/zebra-ssh.desktop"

    # 生成 .desktop 文件
    info "Creating desktop entry..."
    cat > "$INSTALL_DESKTOP/$APP_DESKTOP" << DESKTOP
[Desktop Entry]
Name=$APP_DISPLAY
GenericName=SSH Client
Comment=$APP_COMMENT
Exec=$INSTALL_BIN/$APP_NAME
Icon=$INSTALL_ICON/zebra.png
Terminal=false
Type=Application
StartupWMClass=xin.dart.zebra
Categories=$APP_CATEGORIES
DESKTOP

    # 更新桌面数据库（忽略错误）
    update-desktop-database "$INSTALL_DESKTOP" 2>/dev/null || true
    gtk-update-icon-cache "$INSTALL_ICON" 2>/dev/null || true

    echo
    info "Installed successfully!"
    echo "  Binary:    $INSTALL_BIN/$APP_NAME"
    echo "  Icon:      $INSTALL_ICON/zebra.png"
    echo "  Desktop:   $INSTALL_DESKTOP/$APP_DESKTOP"
    echo
    echo "  You can now launch $APP_DISPLAY from your application menu."
    echo "  Or run: $INSTALL_BIN/$APP_NAME"
}

do_uninstall() {
    echo ""
    echo "========================================"
    echo "  $APP_DISPLAY - Uninstall"
    echo "========================================"
    echo

    get_install_dirs

    local removed=0

    for f in \
        "$INSTALL_BIN/$APP_NAME" \
        "$INSTALL_ICON/zebra.png" \
        "$INSTALL_DESKTOP/$APP_DESKTOP" \
        "$INSTALL_DESKTOP/zebra-ssh.desktop"; do
        if [ -f "$f" ]; then
            rm -f "$f"
            info "Removed: $f"
            removed=1
        fi
    done

    # 清理解压目录
    local extract_dir="${XDG_DATA_HOME:-$HOME/.local}/$APP_NAME"
    if [ -d "$extract_dir" ]; then
        rm -rf "$extract_dir"
        info "Removed: $extract_dir"
    fi

    # 更新桌面数据库
    update-desktop-database "$INSTALL_DESKTOP" 2>/dev/null || true
    gtk-update-icon-cache "$INSTALL_ICON" 2>/dev/null || true

    if [ "$removed" -eq 1 ]; then
        info "Uninstalled successfully!"
    else
        warn "Nothing to uninstall."
    fi
}

do_status() {
    get_install_dirs

    echo ""
    echo "========================================"
    echo "  $APP_DISPLAY - Status"
    echo "========================================"
    echo

    if [ -f "$INSTALL_BIN/$APP_NAME" ]; then
        info "Binary:  installed at $INSTALL_BIN/$APP_NAME"
    else
        warn "Binary:  not installed"
    fi

    if [ -f "$INSTALL_ICON/zebra.png" ]; then
        info "Icon:    installed at $INSTALL_ICON/zebra.png"
    else
        warn "Icon:    not installed"
    fi

    if [ -f "$INSTALL_DESKTOP/$APP_DESKTOP" ]; then
        info "Desktop: installed at $INSTALL_DESKTOP/$APP_DESKTOP"
    else
        warn "Desktop: not installed"
    fi

    echo
}

# --- 脚本入口 ---

show_help() {
    echo "Usage: $0 [OPTIONS] [BINARY_PATH]"
    echo ""
    echo "Install Zebra SSH to ~/.local/"
    echo ""
    echo "Options:"
    echo "  (no args)       Install from current directory (./zebra)"
    echo "  BINARY_PATH     Install from specified binary"
    echo "  --uninstall     Remove installation"
    echo "  --status        Show installation status"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                       # Install ./zebra"
    echo "  $0 /opt/zebra            # Install /opt/zebra"
    echo "  $0 --uninstall           # Remove installation"
}

case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --uninstall|-u)
        do_uninstall
        ;;
    --status|-s)
        do_status
        ;;
    *)
        do_install "${1:-}"
        ;;
esac
