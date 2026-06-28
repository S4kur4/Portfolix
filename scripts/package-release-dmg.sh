#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${PORTFOLIX_APP_NAME:-Portfolix}"
BUNDLE_ID="${PORTFOLIX_BUNDLE_ID:-app.portfolix.mac}"
HELPER_BUNDLE_ID="${BUNDLE_ID}.PriceUpdater"
VERSION="${PORTFOLIX_VERSION:-0.1.0}"
BUILD_NUMBER="${PORTFOLIX_BUILD_NUMBER:-1}"
COPYRIGHT_TEXT="${PORTFOLIX_COPYRIGHT:-Copyright © 2026 S4kur4. All rights reserved.}"
MIN_SYSTEM_VERSION="${PORTFOLIX_MIN_SYSTEM_VERSION:-15.0}"
SIGN_IDENTITY="${PORTFOLIX_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${PORTFOLIX_NOTARY_PROFILE:-}"
PYTHON_RUNTIME_DIR="${PORTFOLIX_PYTHON_RUNTIME_DIR:-}"
REQUIRE_AKSHARE_RUNTIME="${PORTFOLIX_REQUIRE_AKSHARE_RUNTIME:-0}"

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
APP_HELPERS="$APP_CONTENTS/Helpers"
LOGIN_ITEMS="$APP_CONTENTS/Library/LoginItems"
HELPER_APP="$LOGIN_ITEMS/PortfolixPriceUpdater.app"
HELPER_CONTENTS="$HELPER_APP/Contents"
HELPER_MACOS="$HELPER_CONTENTS/MacOS"
HELPER_RESOURCES="$HELPER_CONTENTS/Resources"
DMG_PATH="$ARTIFACT_DIR/$APP_NAME-$VERSION.dmg"
ICON_NAME="Portfolix"
ICON_SOURCE="$ROOT_DIR/Resources/$ICON_NAME.icon"
BRAND_GLYPH_SOURCE="$ROOT_DIR/Resources/PortfolixBrandGlyph.svg"

if [[ "$REQUIRE_AKSHARE_RUNTIME" == "1" && -z "$PYTHON_RUNTIME_DIR" ]]; then
  echo "PORTFOLIX_REQUIRE_AKSHARE_RUNTIME=1 requires PORTFOLIX_PYTHON_RUNTIME_DIR" >&2
  exit 1
fi

if [[ -n "$PYTHON_RUNTIME_DIR" && ! -x "$PYTHON_RUNTIME_DIR/bin/python3" ]]; then
  echo "missing executable python runtime: $PYTHON_RUNTIME_DIR/bin/python3" >&2
  exit 1
fi

if [[ ! -d "$ICON_SOURCE" ]]; then
  echo "missing app icon source: $ICON_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$BRAND_GLYPH_SOURCE" ]]; then
  echo "missing brand glyph source: $BRAND_GLYPH_SOURCE" >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$APP_BUNDLE" "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$MODULE_CACHE_DIR" "$SWIFTPM_CACHE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES/Helpers" "$APP_HELPERS" "$HELPER_MACOS" "$HELPER_RESOURCES/Helpers" "$STAGING_DIR"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
swift build \
  --package-path "$ROOT_DIR" \
  --configuration release \
  --scratch-path "$BUILD_DIR" \
  --cache-path "$SWIFTPM_CACHE_DIR"

BIN_DIR="$(CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" swift build --package-path "$ROOT_DIR" --configuration release --scratch-path "$BUILD_DIR" --cache-path "$SWIFTPM_CACHE_DIR" --show-bin-path)"
cp "$BIN_DIR/$APP_NAME" "$APP_MACOS/$APP_NAME"
cp "$BIN_DIR/PortfolixPriceUpdater" "$HELPER_MACOS/PortfolixPriceUpdater"
chmod +x "$APP_MACOS/$APP_NAME" "$HELPER_MACOS/PortfolixPriceUpdater"

cp "$ROOT_DIR/Helpers/portfolix-akshare-bridge.py" "$APP_RESOURCES/Helpers/portfolix-akshare-bridge.py"
cp "$ROOT_DIR/Helpers/portfolix-akshare-bridge.py" "$HELPER_RESOURCES/Helpers/portfolix-akshare-bridge.py"
cp "$BRAND_GLYPH_SOURCE" "$APP_RESOURCES/PortfolixBrandGlyph.svg"

if [[ -n "$PYTHON_RUNTIME_DIR" ]]; then
  ditto "$PYTHON_RUNTIME_DIR" "$APP_HELPERS/python-runtime"
fi

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

if [[ -d "$APP_HELPERS/python-runtime" ]]; then
  while IFS= read -r item; do
    if [[ -f "$item" && -x "$item" ]]; then
      sign_path "$item" || true
    fi
  done < <(find "$APP_HELPERS/python-runtime" -type f)
fi

sign_path "$HELPER_APP"
sign_path "$APP_BUNDLE"

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "$DMG_PATH"
