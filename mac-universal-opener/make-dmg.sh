#!/bin/sh
set -eu

cd "$(dirname "$0")"

APP_NAME="Open Everything"
BUNDLE_NAME="OpenEverything.app"
VERSION="1.11.0"
OUTPUT_DIR="$PWD/dist"
APP_DIR="$OUTPUT_DIR/$BUNDLE_NAME"
DMG_PATH="$PWD/OpenEverything-$VERSION.dmg"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script must be run on macOS. Apple’s Swift compiler and hdiutil are required." >&2
  exit 1
fi

BUILD_LOG="$PWD/build-output.log"
if ! sh build-app.sh >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG" >&2
  grep -E "error:|warning:" "$BUILD_LOG" | while IFS= read -r line; do
    safe_line=$(printf "%s" "$line" | sed 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g')
    printf "::error::%s\n" "$safe_line"
  done
  exit 1
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/$BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/READ ME - If macOS Says Damaged.txt" <<'HELP'
OPEN EVERYTHING — FIRST LAUNCH HELP

1. Drag OpenEverything.app into the Applications folder.
2. Right-click OpenEverything.app and choose Open.
3. If macOS says the app is damaged or cannot be opened, open Terminal,
   paste the command below, press Return, and enter your Mac password:

sudo xattr -rd com.apple.quarantine "/Applications/OpenEverything.app"

Terminal does not display password characters while you type.
This command removes the download quarantine attribute from this app only.
It does not disable Gatekeeper system-wide.
HELP

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

if [ -n "$SIGNING_IDENTITY" ]; then
  echo "Signing DMG…"
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"

  if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
    echo "Submitting DMG to Apple notarization service…"
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait

    echo "Stapling notarization ticket…"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
  else
    echo "Apple notarization credentials are absent; delivering a signed, unnotarized DMG."
  fi
else
  echo "Developer ID is absent; delivering an unsigned DMG."
fi

if [ -n "${GITHUB_ACTIONS:-}" ]; then
  AUTH_HEADER=$(git config --local --get http.https://github.com/.extraheader)
  ENCODED_TOKEN=$(printf "%s" "$AUTH_HEADER" | awk '{print $3}')
  GH_TOKEN=$(printf "%s" "$ENCODED_TOKEN" | base64 --decode | cut -d: -f2-)
  export GH_TOKEN
  TAG="v$VERSION"
  gh release view "$TAG" >/dev/null 2>&1 || \
    gh release create "$TAG" \
      --target "${GITHUB_SHA:-main}" \
      --title "Open Everything $VERSION" \
      --notes "Includes built-in Linux and Windows virtual machines using Apple Virtualization, NES emulation, native 3D viewing, app wrappers, and safe Trash deletion."
  gh release upload "$TAG" "$DMG_PATH" --clobber

  git config user.name "Open Everything Build"
  git config user.email "actions@users.noreply.github.com"
  git checkout -B dmg-output
  git add -f "$DMG_PATH"
  git commit -m "Publish Open Everything $VERSION DMG"
  git push --force origin HEAD:dmg-output
fi

echo "Created: $DMG_PATH"
