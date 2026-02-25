#!/bin/bash
set -euo pipefail

APP_NAME="Speex"
SCHEME="Speex"
CONFIG="Release"
BUILD_DIR="$(mktemp -d)"
DMG_DIR="$(mktemp -d)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"

STORAGE_BUCKET="whisper-f6336.firebasestorage.app"
STORAGE_BASE_URL="https://firebasestorage.googleapis.com/v0/b/$STORAGE_BUCKET/o"

echo "=== Building $APP_NAME ($CONFIG) — without embedded model ==="
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE="Manual" \
    SPEEX_SKIP_EMBED_MODEL=1 \
    2>&1 | tail -5

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found"
    exit 1
fi

# Re-sign with developer certificate + entitlements for Keychain access
echo "=== Signing with developer certificate ==="
ENTITLEMENTS="$PROJECT_DIR/Speex/Resources/Speex.entitlements"
codesign --force --deep --sign "Apple Development: andresilvagomez@gmail.com (7NBJJ9P97F)" --entitlements "$ENTITLEMENTS" "$APP_PATH"

# Get version for filename
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
BUILD_NUMBER=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "1")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

# Prepare DMG contents
echo "=== Creating DMG ==="
mkdir -p "$DMG_DIR/$APP_NAME"
cp -R "$APP_PATH" "$DMG_DIR/$APP_NAME/"
ln -s /Applications "$DMG_DIR/$APP_NAME/Applications"

# Create DMG
mkdir -p "$OUTPUT_DIR"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR/$APP_NAME" \
    -ov \
    -format UDZO \
    "$OUTPUT_DIR/$DMG_NAME"

# === Sparkle: sign DMG and generate appcast ===
echo "=== Signing DMG for Sparkle auto-updates ==="

# Find Sparkle tools in DerivedData or resolved packages
SPARKLE_BIN=""
for candidate in \
    "$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin" \
    "$HOME/Library/Developer/Xcode/DerivedData"/Speex-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
    if [ -x "$candidate/sign_update" ]; then
        SPARKLE_BIN="$candidate"
        break
    fi
done

if [ -n "$SPARKLE_BIN" ]; then
    SIGNATURE=$("$SPARKLE_BIN/sign_update" "$OUTPUT_DIR/$DMG_NAME" 2>/dev/null || true)
    if [ -n "$SIGNATURE" ]; then
        echo "EdDSA signature: $SIGNATURE"

        DMG_SIZE=$(stat -f%z "$OUTPUT_DIR/$DMG_NAME")
        PUB_DATE=$(date -R)
        DMG_URL="https://firebasestorage.googleapis.com/v0/b/$STORAGE_BUCKET/o/releases%2F$DMG_NAME?alt=media"

        cat > "$OUTPUT_DIR/appcast.xml" <<APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$APP_NAME</title>
    <link>https://speex.co</link>
    <description>Actualizaciones de $APP_NAME</description>
    <language>es</language>
    <item>
      <title>$APP_NAME $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="$DMG_URL"
        $SIGNATURE
        length="$DMG_SIZE"
        type="application/octet-stream" />
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
APPCAST_EOF
        echo "Appcast: $OUTPUT_DIR/appcast.xml"

        # Upload to Firebase Storage
        echo ""
        echo "=== Uploading to Firebase Storage ==="
        UPLOAD_SCRIPT="$SCRIPT_DIR/upload-to-storage.js"

        node "$UPLOAD_SCRIPT" "$OUTPUT_DIR/$DMG_NAME" "releases/$DMG_NAME" "application/x-apple-diskimage"
        node "$UPLOAD_SCRIPT" "$OUTPUT_DIR/$DMG_NAME" "releases/Speex-latest.dmg" "application/x-apple-diskimage"

        # Copy appcast to Firebase Hosting public dir
        mkdir -p "$PROJECT_DIR/public/releases"
        cp "$OUTPUT_DIR/appcast.xml" "$PROJECT_DIR/public/releases/appcast.xml"

        # Deploy hosting (serves appcast.xml from speex.co/releases/appcast.xml)
        echo ""
        echo "=== Deploying to Firebase Hosting ==="
        (cd "$PROJECT_DIR" && firebase deploy --only hosting)

        echo ""
        echo "=== Uploaded ==="
        echo "DMG:     $DMG_URL"
        echo "Appcast: https://speex.co/releases/appcast.xml"
    else
        echo "WARNING: Could not sign DMG (missing key in keychain?)"
    fi
else
    echo "WARNING: Sparkle sign_update not found. Skipping appcast generation."
fi

# Cleanup
rm -rf "$BUILD_DIR" "$DMG_DIR"

echo ""
echo "=== Done ==="
echo "DMG: $OUTPUT_DIR/$DMG_NAME"
echo "Size: $(du -h "$OUTPUT_DIR/$DMG_NAME" | cut -f1)"
echo ""
echo "Instrucciones para tus amigos:"
echo "  1. Ir a https://speex.co/download y abrir el DMG"
echo "  2. Arrastrar Speex a Aplicaciones"
echo "  3. Abrir Terminal y ejecutar:"
echo "     xattr -cr /Applications/Speex.app"
echo "  4. Abrir Speex (clic derecho > Abrir la primera vez)"
echo "  5. Conceder permisos de Micrófono y Accesibilidad"
