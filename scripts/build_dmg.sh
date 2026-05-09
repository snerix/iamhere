#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Here.xcodeproj"
SCHEME="Here"
CONFIGURATION="Release"
INFO_PLIST="$ROOT_DIR/Here/Resources/Info.plist"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/HereReleaseDerivedData}"
STAGING_DIR="${STAGING_DIR:-/private/tmp/HereDMG}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Here.app"
DMG_PATH="$DIST_DIR/Here-$VERSION.dmg"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--clean]

Builds Here.app in Release configuration and creates:
  $DMG_PATH

Environment overrides:
  DERIVED_DATA_PATH  Default: /private/tmp/HereReleaseDerivedData
  STAGING_DIR        Default: /private/tmp/HereDMG
  DIST_DIR           Default: <repo>/dist
EOF
}

CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "==> Building Here $VERSION ($BUILD)"
if [[ "$CLEAN" -eq 1 ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    clean
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH" >&2
  exit 1
fi

echo "==> Staging DMG contents"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
ditto "$APP_PATH" "$STAGING_DIR/Here.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Here" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Done"
echo "$DMG_PATH"
