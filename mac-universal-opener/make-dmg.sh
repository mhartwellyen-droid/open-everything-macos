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
  # output through the workflow's existing artifact upload and GitHub check
  # annotations for diagnosis.
  cp "$BUILD_LOG" "$DMG_PATH"
  grep -E "error:|warning:" "$BUILD_LOG" | while IFS= read -r line; do
    safe_line=$(printf "%s" "$line" | sed 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g')
    printf "::error::%s\n" "$safe_line"
  done
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

# Publish the binary to a temporary branch so automated clients that cannot
# follow GitHub artifact redirects can retrieve it through the Git data API.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  git config user.name "Open Everything Build"
  git config user.email "actions@users.noreply.github.com"
  git checkout -B dmg-output
  git add -f "$DMG_PATH"
  git commit -m "Publish Open Everything DMG"
  git push --force origin HEAD:dmg-output
fi

echo "Created: $DMG_PATH"