#!/bin/sh
set -eu

cd "$(dirname "$0")"

APP_NAME="Open Everything"
BUNDLE_NAME="OpenEverything.app"
OUTPUT_DIR="$PWD/dist"
APP_DIR="$OUTPUT_DIR/$BUNDLE_NAME"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"

echo "Building Open Everything…"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/OpenEverything" "$APP_DIR/Contents/MacOS/OpenEverything"
cp "Sources/OpenEverything/Resources/jsnes.min.js" "$APP_DIR/Contents/Resources/"
cp "Sources/OpenEverything/Resources/JSNES-LICENSE.txt" "$APP_DIR/Contents/Resources/"

ICON_SOURCE="Sources/OpenEverything/Resources/AppIcon.png"
ICONSET="$OUTPUT_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"


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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Open Everything</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.10.0</string>
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

cat > "$OUTPUT_DIR/OpenEverything.entitlements" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.virtualization</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

if [ -n "$SIGNING_IDENTITY" ]; then
  echo "Signing $BUNDLE_NAME with Developer ID…"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$OUTPUT_DIR/OpenEverything.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"

  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
elif [ "$REQUIRE_SIGNING" = "1" ]; then
  echo "DEVELOPER_ID_APPLICATION is required when REQUIRE_SIGNING=1." >&2
  exit 1
else
  echo "Applying an ad-hoc signature for local distribution…"
  codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$OUTPUT_DIR/OpenEverything.entitlements" \
    "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "Built: $APP_DIR"
echo "You can drag it into your Applications folder."
