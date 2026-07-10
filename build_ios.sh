#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DART_DEFINE="--dart-define=BUILD_TIME=$BUILD_TIME"

show_menu() {
    clear
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Build Tools (iOS)"
    echo "========================================"
    echo ""
    echo "  [1] Build iOS (release)"
    echo "  [2] Build IPA (for distribution)"
    echo "  [3] Build + Run on simulator"
    echo "  [4] Clean build artifacts"
    echo "  [5] Clean + Build"
    echo "  [6] Exit"
    echo ""
}

do_clean() {
    echo ""
    echo "Cleaning build artifacts..."
    rm -rf "$SCRIPT_DIR/build"
    rm -rf "$SCRIPT_DIR/ios/Pods"
    rm -rf "$SCRIPT_DIR/ios/.symlinks"
    rm -rf "$SCRIPT_DIR/ios/Flutter/ephemeral"
    rm -rf "$SCRIPT_DIR/.dart_tool"
    echo "Done!"
}

do_build_ios() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - iOS Build"
    echo "========================================"
    echo

    echo "[1/3] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/3] Installing CocoaPods..."
    cd ios
    pod install --repo-update
    if [ $? -ne 0 ]; then
        echo "[ERROR] pod install failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi
    cd "$SCRIPT_DIR"

    echo
    echo "[3/3] Building Flutter iOS release..."
    flutter build ios --release --no-codesign $DART_DEFINE
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "Done!"
    echo "Build output: $SCRIPT_DIR/build/ios/iphoneos/Runner.app"
}

do_build_ipa() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - iOS IPA Build"
    echo "========================================"
    echo

    echo "[1/3] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/3] Installing CocoaPods..."
    cd ios
    pod install --repo-update
    if [ $? -ne 0 ]; then
        echo "[ERROR] pod install failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi
    cd "$SCRIPT_DIR"

    echo
    echo "[3/3] Building Flutter iOS IPA..."
    flutter build ipa --release $DART_DEFINE
    if [ $? -ne 0 ]; then
        echo "[ERROR] Flutter build failed!"
        return 1
    fi

    echo
    echo "Done!"
    echo "IPA output: $SCRIPT_DIR/build/ios/ipa/"
    ls -lh "$SCRIPT_DIR/build/ios/ipa/"*.ipa 2>/dev/null
}

do_build_run_sim() {
    cd "$SCRIPT_DIR"
    echo ""
    echo "========================================"
    echo "  Zebra SSH - Build + Run (Simulator)"
    echo "========================================"
    echo

    echo "[1/3] Running flutter pub get..."
    flutter pub get
    if [ $? -ne 0 ]; then
        echo "[ERROR] flutter pub get failed!"
        return 1
    fi

    echo
    echo "[2/3] Installing CocoaPods..."
    cd ios
    pod install --repo-update
    if [ $? -ne 0 ]; then
        echo "[ERROR] pod install failed!"
        cd "$SCRIPT_DIR"
        return 1
    fi
    cd "$SCRIPT_DIR"

    echo
    echo "[3/3] Building and running on simulator..."
    flutter run --release $DART_DEFINE
    if [ $? -ne 0 ]; then
        echo "[ERROR] Build/run failed!"
        return 1
    fi
}

# 兼容旧用法: ./build_ios.sh --clean 或 ./build_ios.sh
if [ "$1" = "--clean" ]; then
    do_clean
    do_build_ios
    exit 0
fi

# 交互式菜单
while true; do
    show_menu
    read -p "  Select option [1-6]: " choice

    case $choice in
        1) do_build_ios ;;
        2) do_build_ipa ;;
        3) do_build_run_sim ;;
        4) do_clean ;;
        5) do_clean; do_build_ios ;;
        6) exit 0 ;;
        *) echo "Invalid option!" ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
