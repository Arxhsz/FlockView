#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/release"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flockview-release.XXXXXX")"
DERIVED_DATA="$WORK_DIR/DerivedData"
STAGING_DIR="$WORK_DIR/FlockView"
APP_PATH="$DERIVED_DATA/Build/Products/Release/FlockView.app"
DMG_PATH="$BUILD_DIR/FlockView-macOS.dmg"
ZIP_PATH="$BUILD_DIR/FlockView-macOS.zip"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DERIVED_DATA" "$STAGING_DIR"

# Codesign rejects resource forks and Finder metadata inside app bundles. Clear
# extended attributes from local assets before Xcode compiles them into Assets.car.
xattr -cr "$ROOT_DIR/FlockView/Assets.xcassets" "$ROOT_DIR/docs/assets" 2>/dev/null || true

xcodebuild \
  -project FlockView.xcodeproj \
  -scheme FlockView \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release build did not produce $APP_PATH" >&2
  exit 1
fi

cp -R "$APP_PATH" "$STAGING_DIR/FlockView.app"
xattr -cr "$STAGING_DIR/FlockView.app" 2>/dev/null || true
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "FlockView" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

cat <<EOF
Release artifacts created:
  $DMG_PATH
  $ZIP_PATH

Install from the DMG by dragging FlockView.app into Applications.
EOF
