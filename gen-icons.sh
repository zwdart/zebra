#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
    echo ""
    echo "Usage: ./gen-icons.sh <svg-file>"
    echo "Example: ./gen-icons.sh assets/icons/icon.svg"
    echo ""
    exit 1
fi

if [ ! -f "$1" ]; then
    echo ""
    echo "Error: SVG file not found: $1"
    echo ""
    exit 1
fi

# 构建 icon-gen (如果不存在)
if [ ! -f "$SCRIPT_DIR/packer/target/release/icon-gen" ]; then
    echo "Building icon-gen..."
    cd "$SCRIPT_DIR/packer"
    cargo build --release --bin icon-gen
    cd "$SCRIPT_DIR"
fi

echo ""
echo "Generating icons from: $1"
echo ""
"$SCRIPT_DIR/packer/target/release/icon-gen" "$1"
