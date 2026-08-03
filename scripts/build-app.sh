#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="$(mktemp -d /tmp/zoom98-control-build.XXXXXX)"
APP_DIR="$PROJECT_DIR/dist/Zoom98 Control.app"
trap 'rm -rf "$BUILD_DIR"' EXIT

env \
  CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache" \
  SWIFT_MODULECACHE_PATH="$BUILD_DIR/swift-cache" \
  swift build \
    --disable-sandbox \
    --configuration debug \
    --package-path "$PROJECT_DIR" \
    --scratch-path "$BUILD_DIR/swiftpm"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/swiftpm/out/Products/Debug/Zoom98Mac" "$APP_DIR/Contents/MacOS/Zoom98Mac"
cp "$PROJECT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/App/Resources/Zoom98Control.icns" "$APP_DIR/Contents/Resources/Zoom98Control.icns"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

print "Built: $APP_DIR"
