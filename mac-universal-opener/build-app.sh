#!/bin/sh
set -eu

cd "$(dirname "$0")"

APP_NAME="Open Everything"
BUNDLE_NAME="OpenEverything.app"
OUTPUT_DIR="$PWD/dist"
APP_DIR="$OUTPUT_DIR/$BUNDLE_NAME"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"
WINE_VERSION="11.17"
WINE_ARCHIVE="$PWD/.build/wine-staging-$WINE_VERSION-osx64.tar.xz"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VERSION/wine-staging-$WINE_VERSION-osx64.tar.xz"

echo "Building Open Everything…"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/OpenEverything" "$APP_DIR/Contents/MacOS/OpenEverything"
cp "Sources/OpenEverything/Resources/jsnes.min.js" "$APP_DIR/Contents/Resources/"
cp "Sources/OpenEverything/Resources/JSNES-LICENSE.txt" "$APP_DIR/Contents/Resources/"

if [ ! -f "$WINE_ARCHIVE" ]; then
  echo "Downloading Wine Staging $WINE_VERSION runtime…"
  curl -L --fail --retry 3 -o "$WINE_ARCHIVE" "$WINE_URL"
fi
WINE_EXTRACT="$PWD/.build/wine-runtime-$WINE_VERSION"
rm -rf "$WINE_EXTRACT"
mkdir -p "$WINE_EXTRACT"
tar -xf "$WINE_ARCHIVE" -C "$WINE_EXTRACT"
cp -R \
  "$WINE_EXTRACT/Wine Staging.app/Contents/Resources/wine" \
  "$APP_DIR/Contents/Resources/WineRuntime"
cp "Sources/OpenEverything/Resources/WINE-RUNTIME-NOTICE.txt" \
  "$APP_DIR/Contents/Resources/"
test -x "$APP_DIR/Contents/Resources/WineRuntime/bin/wine"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Open Everything</string>
    <key>CFBundleExecutable</key>
    <string>OpenEverything</string>
    <key>CFBundleIdentifier</key>
    <string>app.openeverything.viewer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Open Everything</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>All Files</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.item</string>
                <string>public.data</string>
                <string>public.content</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -n "$SIGNING_IDENTITY" ]; then
  echo "Signing $BUNDLE_NAME with Developer ID…"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"

  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
elif [ "$REQUIRE_SIGNING" = "1" ]; then
  echo "DEVELOPER_ID_APPLICATION is required when REQUIRE_SIGNING=1." >&2
  exit 1
else
  echo "Applying an ad-hoc signature for local distribution…"
  codesign --force --deep --sign - "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "Built: $APP_DIR"
echo "You can drag it into your Applications folder."
