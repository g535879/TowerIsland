#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Tower Island"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BRIDGE_INSTALL_DIR="$HOME/.tower-island/bin"
CLI_SRC="$PROJECT_DIR/Scripts/tower-island"
CLI_LIB_DIR="$PROJECT_DIR/Scripts/lib"
APP_CLI_DIR="$APP_BUNDLE/Contents/Resources/cli"

cd "$PROJECT_DIR"

echo "==> Building Tower Island..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_CLI_DIR/lib"

ICON_SRC="$PROJECT_DIR/Assets/app-icon.png"
ICON_WORK="$BUILD_DIR/app-icon-normalized.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
if [[ -f "$ICON_SRC" ]]; then
    echo "==> Building app icon..."
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    # Normalize to PNG (source may be JPEG with a .png name) so iconutil accepts the iconset.
    sips -s format png "$ICON_SRC" --out "$ICON_WORK" >/dev/null
    sips -z 16 16 "$ICON_WORK" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_WORK" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_WORK" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_WORK" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_WORK" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_WORK" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_WORK" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_WORK" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_WORK" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_WORK" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR" "$ICON_WORK"
else
    echo "Warning: $ICON_SRC not found; app bundle will have no custom icon."
fi

cp "$BUILD_DIR/release/TowerIsland" "$APP_BUNDLE/Contents/MacOS/TowerIsland"
cp "$BUILD_DIR/release/DIBridge" "$APP_BUNDLE/Contents/MacOS/di-bridge"
cp "$CLI_SRC" "$APP_CLI_DIR/tower-island"
cp "$CLI_LIB_DIR/tower-island-cli.sh" "$APP_CLI_DIR/lib/tower-island-cli.sh"
codesign -s - -f "$APP_BUNDLE/Contents/MacOS/di-bridge" 2>/dev/null || true
codesign -s - -f "$APP_BUNDLE/Contents/MacOS/TowerIsland" 2>/dev/null || true

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Tower Island</string>
    <key>CFBundleDisplayName</key>
    <string>Tower Island</string>
    <key>CFBundleIdentifier</key>
    <string>dev.towerisland.app</string>
    <key>CFBundleVersion</key>
    <string>1.2.4</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.4</string>
    <key>CFBundleExecutable</key>
    <string>TowerIsland</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Tower Island needs Apple Events access to jump to terminal tabs.</string>
</dict>
</plist>
PLIST

if [[ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist"
fi

cat > "$APP_BUNDLE/Contents/PkgInfo" << 'EOF'
APPL????
EOF

echo "==> Installing bridge binary..."
mkdir -p "$BRIDGE_INSTALL_DIR"
cp "$BUILD_DIR/release/DIBridge" "$BRIDGE_INSTALL_DIR/di-bridge"
chmod +x "$BRIDGE_INSTALL_DIR/di-bridge"
codesign -s - -f "$BRIDGE_INSTALL_DIR/di-bridge" 2>/dev/null || true
cp "$CLI_SRC" "$BRIDGE_INSTALL_DIR/tower-island"
mkdir -p "$BRIDGE_INSTALL_DIR/lib"
cp "$CLI_LIB_DIR/tower-island-cli.sh" "$BRIDGE_INSTALL_DIR/lib/tower-island-cli.sh"
chmod +x "$BRIDGE_INSTALL_DIR/tower-island"

echo ""
echo "Build complete!"
echo "  App:    $APP_BUNDLE"
echo "  Bridge: $BRIDGE_INSTALL_DIR/di-bridge"
echo "  CLI:    $BRIDGE_INSTALL_DIR/tower-island"
echo ""
echo "To install, run:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "Or run directly:"
echo "  open \"$APP_BUNDLE\""
