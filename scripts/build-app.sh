#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
BUILD_DIR="$ROOT_DIR/.build"
APP_VERSION="0.1.0"
BUILD_NUMBER="6"
COPYRIGHT_TEXT="Copyright © 2026 S4kur4. All rights reserved."
EXECUTABLE="$BUILD_DIR/arm64-apple-macosx/debug/Portfolix"
HELPER_EXECUTABLE="$BUILD_DIR/arm64-apple-macosx/debug/PortfolixPriceUpdater"
APP_DIR="$BUILD_DIR/Portfolix.app"
HELPER_APP_DIR="$APP_DIR/Contents/Library/LoginItems/PortfolixPriceUpdater.app"

if [[ "${1:-}" != "--skip-build" ]]; then
  mkdir -p "$BUILD_DIR/ModuleCache" "$BUILD_DIR/SwiftPMCache"
  CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/ModuleCache" \
    swift build \
      --package-path "$ROOT_DIR" \
      --scratch-path "$BUILD_DIR" \
      --cache-path "$BUILD_DIR/SwiftPMCache"
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  print -u2 "Missing executable: $EXECUTABLE"
  exit 1
fi
if [[ ! -x "$HELPER_EXECUTABLE" ]]; then
  print -u2 "Missing helper executable: $HELPER_EXECUTABLE"
  exit 1
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$HELPER_APP_DIR/Contents/MacOS" "$HELPER_APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Portfolix"

cat > "$HELPER_APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>PortfolixPriceUpdater</string>
  <key>CFBundleIdentifier</key>
  <string>app.portfolix.mac.PriceUpdater</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Portfolix Price Updater</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>NSHumanReadableCopyright</key>
  <string>$COPYRIGHT_TEXT</string>
  <key>LSBackgroundOnly</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
</dict>
</plist>
PLIST
cp "$HELPER_EXECUTABLE" "$HELPER_APP_DIR/Contents/MacOS/PortfolixPriceUpdater"

codesign --force --sign - "$HELPER_APP_DIR"
codesign --force --sign - "$APP_DIR"
print "$APP_DIR"
