#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WalkAway"
BUNDLE_ID="com.fizday.walkaway"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="WalkAway.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "WatchAway" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

swift "$ROOT_DIR/script/generate_app_icon.swift"
iconutil -c icns "$ROOT_DIR/Resources/WalkAway.iconset" -o "$ROOT_DIR/Resources/$ICON_FILE"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/$ICON_FILE" "$APP_RESOURCES/$ICON_FILE"
cp "$ROOT_DIR/Resources/WalkAwayStatusIcon.png" "$APP_RESOURCES/WalkAwayStatusIcon.png"
cp "$ROOT_DIR/Resources/WalkAwayStatusIcon@2x.png" "$APP_RESOURCES/WalkAwayStatusIcon@2x.png"
cp "$ROOT_DIR/Resources/WalkAwayStatusIcon@3x.png" "$APP_RESOURCES/WalkAwayStatusIcon@3x.png"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>WalkAway</string>
  <key>CFBundleIconName</key>
  <string>WalkAway</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSApplicationActivationPolicy</key>
  <string>Accessory</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Detects when your watch leaves to lock the Mac.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
