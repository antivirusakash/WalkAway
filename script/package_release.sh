#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WalkAway"
BUNDLE_ID="com.fizday.walkaway"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="13.0"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Fizday Tech (OPC) Private Limited (BSX8KAUXDZ)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-FizdayNotaryProfile}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
UNIVERSAL="${UNIVERSAL:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_ROOT="$RELEASE_DIR/dmg-root"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
ICON_FILE="$APP_NAME.icns"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$DMG_ROOT"

if [[ "$UNIVERSAL" == "1" ]] && xcrun --find xcodebuild >/dev/null 2>&1; then
  swift build -c release --arch arm64 --arch x86_64
  BUILD_BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
  if [[ "$UNIVERSAL" == "1" ]]; then
    echo "warning: xcbuild is unavailable; building current-architecture release for v0 testing" >&2
    echo "warning: install/select full Xcode before final universal website distribution" >&2
  fi
  swift build -c release
  BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

swift "$ROOT_DIR/script/generate_app_icon.swift"
iconutil -c icns "$ROOT_DIR/Resources/$APP_NAME.iconset" -o "$ROOT_DIR/Resources/$ICON_FILE"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/$ICON_FILE" "$APP_RESOURCES/$ICON_FILE"
cp "$ROOT_DIR/Resources/${APP_NAME}StatusIcon.png" "$APP_RESOURCES/${APP_NAME}StatusIcon.png"
cp "$ROOT_DIR/Resources/${APP_NAME}StatusIcon@2x.png" "$APP_RESOURCES/${APP_NAME}StatusIcon@2x.png"
cp "$ROOT_DIR/Resources/${APP_NAME}StatusIcon@3x.png" "$APP_RESOURCES/${APP_NAME}StatusIcon@3x.png"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSApplicationActivationPolicy</key>
  <string>Accessory</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Detects when your watch leaves to lock the Mac.</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Fizday Tech (OPC) Private Limited. All rights reserved.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_BUNDLE"
codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
  else
    echo "warning: notary profile '$NOTARY_PROFILE' is not configured; created signed DMG without notarization" >&2
    echo "warning: run xcrun notarytool store-credentials '$NOTARY_PROFILE' before final website distribution" >&2
  fi
fi

codesign -dvvv "$APP_BUNDLE" 2>&1 | sed -n '1,24p'
spctl -a -vv "$APP_BUNDLE" 2>&1 || true

echo "$DMG_PATH"
