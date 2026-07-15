#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${PORTFOLIX_APP_NAME:-Portfolix}"
EXECUTABLE_NAME="${PORTFOLIX_EXECUTABLE_NAME:-Portfolix}"
BUNDLE_ID="${PORTFOLIX_BUNDLE_ID:-app.portfolix.mac}"
HELPER_BUNDLE_ID="${BUNDLE_ID}.PriceUpdater"
VERSION="${PORTFOLIX_VERSION:-0.1.4}"
BUILD_NUMBER="${PORTFOLIX_BUILD_NUMBER:-12}"
COPYRIGHT_TEXT="${PORTFOLIX_COPYRIGHT:-Copyright © 2026 S4kur4. All rights reserved.}"
MIN_SYSTEM_VERSION="${PORTFOLIX_MIN_SYSTEM_VERSION:-15.0}"
SIGN_IDENTITY="${PORTFOLIX_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${PORTFOLIX_NOTARY_PROFILE:-}"
SKIP_SWIFT_BUILD="${PORTFOLIX_SKIP_SWIFT_BUILD:-0}"
BIN_DIR_OVERRIDE="${PORTFOLIX_BIN_DIR:-}"
DMG_FILESYSTEM="${PORTFOLIX_DMG_FILESYSTEM:-HFS+}"
SPARKLE_FEED_URL="${PORTFOLIX_SPARKLE_FEED_URL:-https://raw.githubusercontent.com/S4kur4/Portfolix/main/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${PORTFOLIX_SPARKLE_PUBLIC_ED_KEY:-BX7U6Nmwk+IBB5lluFk8rJ3KFopJfeYJS7DFOR+wqZM=}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RELEASE_DIR="$(cd "$ROOT_DIR/.." && pwd)/release"
BUILD_DIR="$ROOT_DIR/.build/release"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
SWIFTPM_CACHE_DIR="$BUILD_DIR/SwiftPMCache"
ARTIFACT_DIR="${PORTFOLIX_RELEASE_DIR:-$DEFAULT_RELEASE_DIR}"
STAGING_DIR="$ARTIFACT_DIR/staging"
APP_BUNDLE="$ARTIFACT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
LOGIN_ITEMS="$APP_CONTENTS/Library/LoginItems"
HELPER_APP="$LOGIN_ITEMS/PortfolixPriceUpdater.app"
HELPER_CONTENTS="$HELPER_APP/Contents"
HELPER_MACOS="$HELPER_CONTENTS/MacOS"
HELPER_RESOURCES="$HELPER_CONTENTS/Resources"
DMG_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.dmg"
TEMP_DMG_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.tmp.dmg"
ICON_NAME="Portfolix"
ICON_SOURCE="$ROOT_DIR/Resources/$ICON_NAME.icon"
BRAND_GLYPH_SOURCE="$ROOT_DIR/Resources/PortfolixBrandGlyph.svg"
SPARKLE_FRAMEWORK_SOURCE="$ROOT_DIR/.build/release/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if [[ ! -d "$ICON_SOURCE" ]]; then
  echo "missing app icon source: $ICON_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$BRAND_GLYPH_SOURCE" ]]; then
  echo "missing brand glyph source: $BRAND_GLYPH_SOURCE" >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$APP_BUNDLE" "$TEMP_DMG_PATH" "$TEMP_DMG_PATH.sha256"
mkdir -p "$MODULE_CACHE_DIR" "$SWIFTPM_CACHE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS" "$HELPER_MACOS" "$HELPER_RESOURCES" "$STAGING_DIR"

if [[ "$SKIP_SWIFT_BUILD" != "1" ]]; then
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
  swift build \
    --package-path "$ROOT_DIR" \
    --configuration release \
    --scratch-path "$BUILD_DIR" \
    --cache-path "$SWIFTPM_CACHE_DIR"
fi

if [[ -n "$BIN_DIR_OVERRIDE" ]]; then
  BIN_DIR="$BIN_DIR_OVERRIDE"
elif [[ "$SKIP_SWIFT_BUILD" == "1" ]]; then
  BIN_DIR=""
  for candidate in \
    "$BUILD_DIR/arm64-apple-macosx/release" \
    "$BUILD_DIR/x86_64-apple-macosx/release" \
    "$BUILD_DIR/release"
  do
    if [[ -x "$candidate/$EXECUTABLE_NAME" && -x "$candidate/PortfolixPriceUpdater" ]]; then
      BIN_DIR="$candidate"
      break
    fi
  done
  if [[ -z "$BIN_DIR" ]]; then
    echo "PORTFOLIX_SKIP_SWIFT_BUILD=1 could not locate release binaries under $BUILD_DIR" >&2
    exit 1
  fi
else
  BIN_DIR="$(CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" swift build --package-path "$ROOT_DIR" --configuration release --scratch-path "$BUILD_DIR" --cache-path "$SWIFTPM_CACHE_DIR" --show-bin-path)"
fi

if [[ ! -x "$BIN_DIR/$EXECUTABLE_NAME" || ! -x "$BIN_DIR/PortfolixPriceUpdater" ]]; then
  echo "missing release binaries in $BIN_DIR" >&2
  exit 1
fi

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_MACOS/$APP_NAME"
cp "$BIN_DIR/PortfolixPriceUpdater" "$HELPER_MACOS/PortfolixPriceUpdater"
chmod +x "$APP_MACOS/$APP_NAME" "$HELPER_MACOS/PortfolixPriceUpdater"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_MACOS/$APP_NAME" 2>/dev/null || true

if [[ -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  rm -rf "$APP_FRAMEWORKS/Sparkle.framework"
  ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS/Sparkle.framework"
else
  echo "missing Sparkle.framework: $SPARKLE_FRAMEWORK_SOURCE" >&2
  exit 1
fi

cp "$BRAND_GLYPH_SOURCE" "$APP_RESOURCES/PortfolixBrandGlyph.svg"
ditto "$ICON_SOURCE" "$APP_RESOURCES/$ICON_NAME.icon"

xcrun actool \
  --compile "$APP_RESOURCES" \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --app-icon "$ICON_NAME" \
  --output-partial-info-plist "$APP_CONTENTS/Info.plist" \
  "$ICON_SOURCE"

cat >"$APP_CONTENTS/Info.plist" <<PLIST
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
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>NSHumanReadableCopyright</key>
  <string>$COPYRIGHT_TEXT</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconName</key>
  <string>$ICON_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUVerifyUpdateBeforeExtraction bool true" "$APP_CONTENTS/Info.plist"
else
  echo "warning: PORTFOLIX_SPARKLE_PUBLIC_ED_KEY is empty; Sparkle auto-update is disabled for this build." >&2
fi

cat >"$HELPER_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>PortfolixPriceUpdater</string>
  <key>CFBundleIdentifier</key>
  <string>$HELPER_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Portfolix Price Updater</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>NSHumanReadableCopyright</key>
  <string>$COPYRIGHT_TEXT</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSBackgroundOnly</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
</dict>
</plist>
PLIST

sign_path() {
  local path="$1"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign - "$path"
  else
    /usr/bin/codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$path"
  fi
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

sign_sparkle_framework "$APP_FRAMEWORKS/Sparkle.framework"
sign_path "$HELPER_APP"
sign_path "$APP_BUNDLE"

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO -fs "$DMG_FILESYSTEM" "$TEMP_DMG_PATH"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$TEMP_DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$TEMP_DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$TEMP_DMG_PATH"
fi

mv "$TEMP_DMG_PATH" "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "$DMG_PATH"
