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

RESOURCE_DIR="$PWD/Sources/OpenEverything/Resources"
for encoded in "$RESOURCE_DIR"/*.b64; do
  [ -f "$encoded" ] || continue
  decoded=${encoded%.b64}
  base64 --decode "$encoded" > "$decoded"
done

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/OpenEverything" "$APP_DIR/Contents/MacOS/OpenEverything"

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
    <string>1.0.0</string>
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
  echo "Warning: built an unsigned app because DEVELOPER_ID_APPLICATION is not set." >&2
fi

echo "Built: $APP_DIR"
echo "You can drag it into your Applications folder."
