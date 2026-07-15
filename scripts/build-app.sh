#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
BUILD_DIR="$ROOT_DIR/.build"
APP_VERSION="0.1.4"
BUILD_NUMBER="12"
COPYRIGHT_TEXT="Copyright © 2026 S4kur4. All rights reserved."
SPARKLE_FEED_URL="${PORTFOLIX_SPARKLE_FEED_URL:-https://raw.githubusercontent.com/S4kur4/Portfolix/main/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${PORTFOLIX_SPARKLE_PUBLIC_ED_KEY:-BX7U6Nmwk+IBB5lluFk8rJ3KFopJfeYJS7DFOR+wqZM=}"
EXECUTABLE="$BUILD_DIR/arm64-apple-macosx/debug/Portfolix"
HELPER_EXECUTABLE="$BUILD_DIR/arm64-apple-macosx/debug/PortfolixPriceUpdater"
APP_DIR="$BUILD_DIR/Portfolix.app"
APP_FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
HELPER_APP_DIR="$APP_DIR/Contents/Library/LoginItems/PortfolixPriceUpdater.app"
SPARKLE_FRAMEWORK_SOURCE="$BUILD_DIR/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

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

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_FRAMEWORKS_DIR"
mkdir -p "$HELPER_APP_DIR/Contents/MacOS" "$HELPER_APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Portfolix"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/Portfolix" 2>/dev/null || true

if [[ -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  rm -rf "$APP_FRAMEWORKS_DIR/Sparkle.framework"
  ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS_DIR/Sparkle.framework"
else
  print -u2 "Missing Sparkle.framework: $SPARKLE_FRAMEWORK_SOURCE"
  exit 1
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUVerifyUpdateBeforeExtraction bool true" "$APP_DIR/Contents/Info.plist"
fi

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

sign_path() {
  local path="$1"
  /usr/bin/codesign --force --sign - "$path"
}

sign_sparkle_framework() {
  local framework="$1"
  local version_dir="$framework/Versions/B"
  sign_path "$version_dir/Autoupdate"
  sign_path "$version_dir/Updater.app"
  for xpc in "$version_dir"/XPCServices/*.xpc; do
    sign_path "$xpc"
  done
  sign_path "$framework"
}

sign_sparkle_framework "$APP_FRAMEWORKS_DIR/Sparkle.framework"
/usr/bin/codesign --force --sign - "$HELPER_APP_DIR"
/usr/bin/codesign --force --sign - "$APP_DIR"
print "$APP_DIR"
