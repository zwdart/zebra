#!/bin/bash

# Zebra API Server 管理脚本 (Linux / macOS)
# 用法: ./zebra-api.sh [build|run|stop|status|restart|logs]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIMES_DIR="$SCRIPT_DIR/runtimes"
PID_FILE="$RUNTIMES_DIR/zebra-api.pid"
LOG_FILE="$RUNTIMES_DIR/logs/api.log"
BIN_NAME="zebra-api"
BIN_PATH="$SCRIPT_DIR/target/release/$BIN_NAME"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

build() {
    echo -e "${YELLOW}编译 $BIN_NAME ...${NC}"
    cd "$SCRIPT_DIR"
    
    # 使用 musl 静态编译，不依赖系统 glibc
    cargo build --release --features api-server --bin "$BIN_NAME" --target x86_64-unknown-linux-musl
    
    # 将 musl 目标产物复制到 target/release/ 下
    if [ -f "target/x86_64-unknown-linux-musl/release/$BIN_NAME" ]; then
        cp "target/x86_64-unknown-linux-musl/release/$BIN_NAME" "$BIN_PATH"
    fi
    
    if [ -f "$BIN_PATH" ]; then
        echo -e "${GREEN}编译成功: $BIN_PATH${NC}"
    else
        echo -e "${RED}编译失败${NC}"
        exit 1
    fi
}

run() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}已在运行 (PID: $pid)，先执行 stop${NC}"
            exit 1
        fi
        rm -f "$PID_FILE"
    fi

    if [ ! -f "$BIN_PATH" ]; then
        echo -e "${YELLOW}未找到可执行文件，先编译...${NC}"
        build
    fi

    mkdir -p "$RUNTIMES_DIR/logs"

    echo -e "${GREEN}启动 $BIN_NAME ...${NC}"
    cd "$SCRIPT_DIR"
    nohup "$BIN_PATH" "$@" > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo -e "${GREEN}已启动 (PID: $!)${NC}"
    echo "  日志: $LOG_FILE"
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}未运行${NC}"
        return
    fi

    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${YELLOW}停止 (PID: $pid) ...${NC}"
        kill "$pid"
        for i in $(seq 1 10); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
        echo -e "${GREEN}已停止${NC}"
    else
        echo -e "${YELLOW}进程不存在，清理${NC}"
    fi
    rm -f "$PID_FILE"
}

status() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}运行中 (PID: $pid)${NC}"
            return 0
        fi
        rm -f "$PID_FILE"
    fi
    echo -e "${YELLOW}未运行${NC}"
    return 1
}

logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo -e "${YELLOW}日志不存在: $LOG_FILE${NC}"
    fi
}

usage() {
    echo "用法: $0 <command> [options]"
    echo ""
    echo "  build     编译"
    echo "  run       运行 (可加参数: --port 8686)"
    echo "  stop      停止"
    echo "  restart   重启"
    echo "  status    状态"
    echo "  logs      查看日志"
}

case "${1:-}" in
    build)    build ;;
    run)      shift; run "$@" ;;
    stop)     stop ;;
    restart)  shift; stop; sleep 1; run "$@" ;;
    status)   status ;;
    logs)     logs ;;
    *)        usage; [ -n "$1" ] && exit 1 ;;
esac
