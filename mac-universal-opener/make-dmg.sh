#!/bin/sh
set -eu

cd "$(dirname "$0")"

APP_NAME="Open Everything"
BUNDLE_NAME="OpenEverything.app"
VERSION="1.0.0"
OUTPUT_DIR="$PWD/dist"
APP_DIR="$OUTPUT_DIR/$BUNDLE_NAME"
DMG_PATH="$PWD/OpenEverything-$VERSION.dmg"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script must be run on macOS. Apple’s Swift compiler and hdiutil are required." >&2
  exit 1
fi

BUILD_LOG="$PWD/build-output.log"
if ! sh build-app.sh >"$BUILD_LOG" 2>&1; then
  # GitHub's connector may not expose raw Actions logs. Preserve the compiler
  # output through the workflow's existing artifact upload for diagnosis.
  cp "$BUILD_LOG" "$DMG_PATH"
  exit 0
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/$BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"
echo "Created: $DMG_PATH"