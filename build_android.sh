#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

show_menu() {
    clear
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Build Tools (Android)"
    echo "========================================"
    echo ""
    echo "  [1] Build APK (release, all ABIs)"
    echo "  [2] Build APK (split per ABI)"
    echo "  [3] Build App Bundle (release)"
    echo "  [4] Build + Install to device"
    echo "  [5] Clean build artifacts"
    echo "  [6] Clean + Build"
    echo "  [7] Exit"
    echo ""
}

do_clean() {
    echo ""
    echo "Cleaning build artifacts..."
    rm -rf "$SCRIPT_DIR/build"
    rm -rf "$SCRIPT_DIR/android/build"
    rm -rf "$SCRIPT_DIR/android/app/build"
    rm -rf "$SCRIPT_DIR/.dart_tool"
    echo "Done!"
}

do_build_apk() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Android APK Build"
    echo "========================================"
    echo

    echo "[1/2] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/2] Building Flutter Android APK (release)..."
    cat > "$SCRIPT_DIR/lib/build_info.dart" << EOF
// Auto-generated build info - overwritten by build scripts
const String buildTime = '$BUILD_TIME';
EOF
    flutter build apk --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    mv "$APK_PATH" "build/app/outputs/flutter-apk/zebra-release.apk"
    APK_PATH="build/app/outputs/flutter-apk/zebra-release.apk"
    echo
    echo "Done!"
    echo "APK: $SCRIPT_DIR/$APK_PATH"
    ls -lh "$SCRIPT_DIR/$APK_PATH" 2>/dev/null
}

do_build_apk_split() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Android APK Build (Split)"
    echo "========================================"
    echo

    echo "[1/2] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/2] Building Flutter Android APK (split per ABI)..."
    cat > "$SCRIPT_DIR/lib/build_info.dart" << EOF
// Auto-generated build info - overwritten by build scripts
const String buildTime = '$BUILD_TIME';
EOF
    flutter build apk --split-per-abi --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "Done!"
    echo "APKs:"
    cd "$SCRIPT_DIR/build/app/outputs/flutter-apk"
    for f in app-*.apk; do mv "$f" "zebra-${f#app-}"; done
    ls -lh zebra-*.apk 2>/dev/null
    cd "$SCRIPT_DIR"
}

do_build_aab() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Android App Bundle Build"
    echo "========================================"
    echo

    echo "[1/2] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/2] Building Flutter Android App Bundle (release)..."
    cat > "$SCRIPT_DIR/lib/build_info.dart" << EOF
// Auto-generated build info - overwritten by build scripts
const String buildTime = '$BUILD_TIME';
EOF
    flutter build appbundle --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "Done!"
    echo "AAB:"
    AAB_PATH="$SCRIPT_DIR/build/app/outputs/bundle/release/app-release.aab"
    if [ -f "$AAB_PATH" ]; then
        mv "$AAB_PATH" "$SCRIPT_DIR/build/app/outputs/bundle/release/zebra-release.aab"
    fi
    ls -lh "$SCRIPT_DIR/build/app/outputs/bundle/release/"zebra-release.aab 2>/dev/null
}

do_build_install() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Build + Install"
    echo "========================================"
    echo

    echo "[1/2] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/2] Building and installing to device..."
    cat > "$SCRIPT_DIR/lib/build_info.dart" << EOF
// Auto-generated build info - overwritten by build scripts
const String buildTime = '$BUILD_TIME';
EOF
    flutter install --release
    if [ $? -ne 0 ]; then
        echo "[ERROR] Build/install failed!"
        return 1
    fi

    echo
    echo "Done!"
}

# 兼容旧用法: ./build_android.sh --clean 或 ./build_android.sh
if [ "$1" = "--clean" ]; then
    do_clean
    do_build_apk
    exit 0
fi

# 交互式菜单
while true; do
    show_menu
    read -p "  Select option [1-7]: " choice

    case $choice in
        1) do_build_apk ;;
        2) do_build_apk_split ;;
        3) do_build_aab ;;
        4) do_build_install ;;
        5) do_clean ;;
        6) do_clean; do_build_apk ;;
        7) exit 0 ;;
        *) echo "Invalid option!" ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
