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

sh build-app.sh

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