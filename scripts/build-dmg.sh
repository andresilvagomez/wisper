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

echo "=== Building $APP_NAME ($CONFIG) — without embedded model ==="
SPEEX_SKIP_EMBED_MODEL=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE="Manual" \
    SPEEX_REQUIRE_EMBEDDED_MODEL=0 \
    2>&1 | tail -5

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found"
    exit 1
fi

# Re-sign ad-hoc so it runs on any Mac without a specific certificate
echo "=== Signing ad-hoc ==="
codesign --force --deep --sign - "$APP_PATH"

# Get version for filename
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
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

        cat > "$OUTPUT_DIR/appcast.xml" <<APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$APP_NAME</title>
    <link>https://github.com/andresilvagomez/speex</link>
    <description>Actualizaciones de $APP_NAME</description>
    <language>es</language>
    <item>
      <title>$APP_NAME $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="https://github.com/andresilvagomez/speex/releases/download/v$VERSION/$DMG_NAME"
        $SIGNATURE
        length="$DMG_SIZE"
        type="application/octet-stream" />
      <sparkle:version>$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "1")</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
APPCAST_EOF
        echo "Appcast: $OUTPUT_DIR/appcast.xml"
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
echo "Para publicar la actualización:"
echo "  1. git add appcast.xml && git commit && git push"
echo "  2. Crear GitHub Release v$VERSION y subir $DMG_NAME"
echo ""
echo "Instrucciones para tus amigos:"
echo "  1. Descargar y abrir el DMG"
echo "  2. Arrastrar Speex a Aplicaciones"
echo "  3. Abrir Terminal y ejecutar:"
echo "     xattr -cr /Applications/Speex.app"
echo "  4. Abrir Speex (clic derecho > Abrir la primera vez)"
echo "  5. Conceder permisos de Micrófono y Accesibilidad"
