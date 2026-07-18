#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RELEASE_DIR="$(cd "$ROOT_DIR/.." && pwd)/release"
RELEASE_DIR="${PORTFOLIX_RELEASE_DIR:-$DEFAULT_RELEASE_DIR}"
VERSION="${PORTFOLIX_VERSION:-0.1.5}"
SPARKLE_BIN="$ROOT_DIR/.build/release/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$SPARKLE_BIN" ]]; then
  SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
fi

DOWNLOAD_URL_PREFIX="${PORTFOLIX_SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/S4kur4/Portfolix/releases/download/v$VERSION/}"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
ARCHIVE_BASENAME="Portfolix-$VERSION"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_BASENAME.dmg"

if [[ ! -x "$SPARKLE_BIN" ]]; then
  echo "missing Sparkle generate_appcast tool. Run swift package resolve/build first." >&2
  exit 1
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "missing release directory: $RELEASE_DIR" >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "missing release archive: $ARCHIVE_PATH" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/portfolix-sparkle-appcast.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cp -p "$ARCHIVE_PATH" "$WORK_DIR/"
for extension in html md txt; do
  notes_path="$RELEASE_DIR/$ARCHIVE_BASENAME.$extension"
  if [[ -f "$notes_path" ]]; then
    cp -p "$notes_path" "$WORK_DIR/"
  fi
done

"$SPARKLE_BIN" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --embed-release-notes \
  --link "https://github.com/S4kur4/Portfolix/releases" \
  -o "$WORK_DIR/appcast.xml" \
  "$WORK_DIR"

cp "$WORK_DIR/appcast.xml" "$APPCAST_PATH"
cp "$APPCAST_PATH" "$ROOT_DIR/appcast.xml"
echo "$ROOT_DIR/appcast.xml"
