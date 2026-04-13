#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Tower Island"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BRIDGE_INSTALL_DIR="$HOME/.tower-island/bin"

cd "$PROJECT_DIR"

echo "==> Building Tower Island..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/release/TowerIsland" "$APP_BUNDLE/Contents/MacOS/TowerIsland"
cp "$BUILD_DIR/release/DIBridge" "$APP_BUNDLE/Contents/MacOS/di-bridge"

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
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>TowerIsland</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
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

cat > "$APP_BUNDLE/Contents/PkgInfo" << 'EOF'
APPL????
EOF

echo "==> Installing bridge binary..."
mkdir -p "$BRIDGE_INSTALL_DIR"
cp "$BUILD_DIR/release/DIBridge" "$BRIDGE_INSTALL_DIR/di-bridge"
chmod +x "$BRIDGE_INSTALL_DIR/di-bridge"

echo ""
echo "Build complete!"
echo "  App:    $APP_BUNDLE"
echo "  Bridge: $BRIDGE_INSTALL_DIR/di-bridge"
echo ""
echo "To install, run:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "Or run directly:"
echo "  open \"$APP_BUNDLE\""
