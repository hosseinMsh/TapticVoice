#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=========================================="
echo " Building TapticVoice Studio for macOS... "
echo "=========================================="

APP_NAME="TapticVoice"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# Clean old build
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" /tmp/clang-cache

# 1. Compile Swift sources
echo "[1/4] Compiling Swift sources..."
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
swiftc -O \
    -target arm64-apple-macos13 \
    -module-cache-path /tmp/clang-cache \
    -o "$MACOS_DIR/$APP_NAME" \
    Sources/AppMain.swift \
    Sources/Models/HapticEngine.swift \
    Sources/Models/SpeechBridge.swift \
    Sources/Views/MainView.swift \
    Sources/Views/ControlsView.swift \
    Sources/Views/WaveformVisualizer.swift

echo "[2/4] Copying bundle resources..."
cp Sources/Resources/Info.plist "$CONTENTS/Info.plist"
cp Assets/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
cp Sources/Resources/taptic_synth.py "$RESOURCES_DIR/taptic_synth.py"
chmod +x "$RESOURCES_DIR/taptic_synth.py"

echo "[3/4] Ad-hoc codesigning .app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "[4/4] Verifying bundle structure..."
plutil -lint "$CONTENTS/Info.plist"

echo ""
echo "=========================================================="
echo " SUCCESS! Application built successfully at:"
echo " $APP_BUNDLE"
echo "=========================================================="
