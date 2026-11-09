#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/Lunera.app"
DMG_PATH="$PROJECT_DIR/dist/Lunera.dmg"

if [[ ! -d "$APP_DIR" ]]; then
    echo "Missing $APP_DIR. Run Scripts/build.sh first." >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_DIR"

PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lunera-dmg.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT
STAGING_DIR="$PACKAGE_DIR/staging"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/Lunera.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname Lunera -srcfolder "$STAGING_DIR" \
    -format UDZO "$PACKAGE_DIR/Lunera.dmg"
hdiutil verify "$PACKAGE_DIR/Lunera.dmg"
mv -f "$PACKAGE_DIR/Lunera.dmg" "$DMG_PATH"

cd "$PROJECT_DIR/dist"
shasum -a 256 Lunera.dmg > Lunera.dmg.sha256
echo "Packaged: $DMG_PATH"
