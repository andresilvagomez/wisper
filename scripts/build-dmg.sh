#!/bin/bash
set -euo pipefail

APP_NAME="Speex"
SCHEME="Speex"
CONFIG="Release"
BUILD_DIR="$(mktemp -d)"
DMG_DIR="$(mktemp -d)"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/dist"

echo "=== Building $APP_NAME ($CONFIG) ==="
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE="Manual" \
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

# Cleanup
rm -rf "$BUILD_DIR" "$DMG_DIR"

echo ""
echo "=== Done ==="
echo "DMG: $OUTPUT_DIR/$DMG_NAME"
echo "Size: $(du -h "$OUTPUT_DIR/$DMG_NAME" | cut -f1)"
echo ""
echo "Instrucciones para tus amigos:"
echo "  1. Descargar y abrir el DMG"
echo "  2. Arrastrar Speex a Aplicaciones"
echo "  3. Abrir Terminal y ejecutar:"
echo "     xattr -cr /Applications/Speex.app"
echo "  4. Abrir Speex (clic derecho > Abrir la primera vez)"
echo "  5. Conceder permisos de Micrófono y Accesibilidad"
