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

# Auto-detect DEVELOPER_DIR if not set
if [ -z "$DEVELOPER_DIR" ]; then
    if [ -d "/Library/Developer/CommandLineTools" ]; then
        export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
    fi
fi

ARCH=$(uname -m)
TARGET="${ARCH}-apple-macos13"

# Build standalone synthesizer helper if missing
if [ ! -f "$BUILD_DIR/bin/taptic_synth" ]; then
    echo "[0/4] Building standalone synthesizer helper..."
    python3 -m PyInstaller --clean --noconfirm --onefile --name taptic_synth \
        --distpath "$BUILD_DIR/bin" --workpath /tmp/pybuild --specpath /tmp/pyspec \
        Sources/Resources/synth_cli.py
fi

# 1. Compile Swift sources
echo "[1/4] Compiling Swift sources for ${TARGET}..."
swiftc -O \
    -target "${TARGET}" \
    -module-cache-path /tmp/clang-cache \
    -o "$MACOS_DIR/$APP_NAME" \
    Sources/AppMain.swift \
    Sources/Models/HapticEngine.swift \
    Sources/Models/SpeechBridge.swift \
    Sources/Views/MainView.swift \
    Sources/Views/ControlsView.swift \
    Sources/Views/WaveformVisualizer.swift

echo "[2/4] Copying bundle resources & standalone helpers..."
cp Sources/Resources/Info.plist "$CONTENTS/Info.plist"
cp Assets/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
cp "$BUILD_DIR/bin/taptic_synth" "$MACOS_DIR/taptic_synth"
chmod +x "$MACOS_DIR/taptic_synth"

echo "[3/4] Ad-hoc codesigning embedded helpers & .app bundle..."
codesign --force --sign - "$MACOS_DIR/taptic_synth"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "[4/4] Verifying bundle structure..."
plutil -lint "$CONTENTS/Info.plist"

echo ""
echo "=========================================================="
echo " SUCCESS! Application built successfully at:"
echo " $APP_BUNDLE"
echo "=========================================================="
