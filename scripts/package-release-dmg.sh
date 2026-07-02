#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${PORTFOLIX_APP_NAME:-Portfolix}"
BUNDLE_ID="${PORTFOLIX_BUNDLE_ID:-app.portfolix.mac}"
HELPER_BUNDLE_ID="${BUNDLE_ID}.PriceUpdater"
VERSION="${PORTFOLIX_VERSION:-0.1.0}"
BUILD_NUMBER="${PORTFOLIX_BUILD_NUMBER:-7}"
COPYRIGHT_TEXT="${PORTFOLIX_COPYRIGHT:-Copyright © 2026 S4kur4. All rights reserved.}"
MIN_SYSTEM_VERSION="${PORTFOLIX_MIN_SYSTEM_VERSION:-15.0}"
SIGN_IDENTITY="${PORTFOLIX_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${PORTFOLIX_NOTARY_PROFILE:-}"
SKIP_SWIFT_BUILD="${PORTFOLIX_SKIP_SWIFT_BUILD:-0}"
BIN_DIR_OVERRIDE="${PORTFOLIX_BIN_DIR:-}"
DMG_FILESYSTEM="${PORTFOLIX_DMG_FILESYSTEM:-HFS+}"

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
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$HELPER_MACOS" "$HELPER_RESOURCES" "$STAGING_DIR"

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
    if [[ -x "$candidate/$APP_NAME" && -x "$candidate/PortfolixPriceUpdater" ]]; then
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

if [[ ! -x "$BIN_DIR/$APP_NAME" || ! -x "$BIN_DIR/PortfolixPriceUpdater" ]]; then
  echo "missing release binaries in $BIN_DIR" >&2
  exit 1
fi

cp "$BIN_DIR/$APP_NAME" "$APP_MACOS/$APP_NAME"
cp "$BIN_DIR/PortfolixPriceUpdater" "$HELPER_MACOS/PortfolixPriceUpdater"
chmod +x "$APP_MACOS/$APP_NAME" "$HELPER_MACOS/PortfolixPriceUpdater"

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
    codesign --force --sign - "$path"
  else
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$path"
  fi
}

sign_path "$HELPER_APP"
sign_path "$APP_BUNDLE"

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO -fs "$DMG_FILESYSTEM" "$TEMP_DMG_PATH"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$TEMP_DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$TEMP_DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$TEMP_DMG_PATH"
fi

mv "$TEMP_DMG_PATH" "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "$DMG_PATH"
