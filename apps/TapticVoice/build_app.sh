#!/bin/bash
# Compiles TapticVoice Studio via SwiftPM, embeds universal2 Sherpa-ONNX dylibs & tiny EN/FA offline models,
# fixes dylib install names for portability, signs the .app bundle, and verifies zero external dependencies.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="TapticVoice"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
RESOURCES_DIR="$CONTENTS/Resources"
VENDOR_DIR="$DIR/Vendor"

echo "=================================================="
echo " Building TapticVoice Studio (100% Offline App)  "
echo "=================================================="

# Auto-detect DEVELOPER_DIR in restricted CommandLineTools environments
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Library/Developer/CommandLineTools" ]; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

# 0. Ensure offline dependencies & tiny models are present
if [ ! -f "$VENDOR_DIR/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib" ] || [ ! -d "$VENDOR_DIR/Models/fa_IR" ]; then
    echo "[0/5] Fetching offline Sherpa-ONNX runtime and tiny EN/FA models..."
    "$DIR/scripts/fetch_deps.sh"
fi

# 1. Clean & compile SwiftPM release binary (Universal2 when supported, fallback to host arch)
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR/Models" /tmp/clang-cache

echo "[1/5] Compiling SwiftPM release binary..."
ARCH_ARGS=()
if [ "${BUILD_UNIVERSAL:-1}" = "1" ]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

if ! swift build -c release "${ARCH_ARGS[@]}" \
    -Xswiftc -module-cache-path -Xswiftc /tmp/clang-cache \
    -Xcc -fmodules-cache-path=/tmp/clang-cache; then
    echo "Universal build failed; falling back to host architecture ($(uname -m))..."
    swift build -c release \
        -Xswiftc -module-cache-path -Xswiftc /tmp/clang-cache \
        -Xcc -fmodules-cache-path=/tmp/clang-cache
fi

BIN_PATH=$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path 2>/dev/null || swift build -c release --show-bin-path)
if [ ! -f "$BIN_PATH/$APP_NAME" ]; then
    BIN_PATH=$(swift build -c release --show-bin-path)
fi
cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# 2. Bundle Info.plist, Retina icon, and offline models (fa_IR, en_US, shared espeak-ng-data)
echo "[2/5] Copying bundle resources & offline EN/FA models..."
cp "$DIR/Sources/TapticVoice/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp -R "$VENDOR_DIR/Models/fa_IR" "$RESOURCES_DIR/Models/fa_IR"
cp -R "$VENDOR_DIR/Models/en_US" "$RESOURCES_DIR/Models/en_US"
cp -R "$VENDOR_DIR/Models/espeak-ng-data" "$RESOURCES_DIR/Models/espeak-ng-data"

# 3. Embed universal2 dylibs & rewrite @rpath -> @loader_path for complete portability
echo "[3/5] Embedding Sherpa-ONNX & ONNXRuntime dylibs..."
cp "$VENDOR_DIR/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib" "$FRAMEWORKS_DIR/libsherpa-onnx-c-api.dylib"
cp "$VENDOR_DIR/sherpa-onnx/lib/libonnxruntime.dylib" "$FRAMEWORKS_DIR/libonnxruntime.dylib"
chmod 755 "$FRAMEWORKS_DIR/libsherpa-onnx-c-api.dylib" "$FRAMEWORKS_DIR/libonnxruntime.dylib"

install_name_tool -id "@rpath/libonnxruntime.dylib" "$FRAMEWORKS_DIR/libonnxruntime.dylib"
install_name_tool -id "@rpath/libsherpa-onnx-c-api.dylib" "$FRAMEWORKS_DIR/libsherpa-onnx-c-api.dylib"
install_name_tool -change "@rpath/libonnxruntime.dylib" "@loader_path/libonnxruntime.dylib" "$FRAMEWORKS_DIR/libsherpa-onnx-c-api.dylib"

# 4. Ad-hoc codesign embedded libraries and app bundle
echo "[4/5] Codesigning Frameworks and .app bundle..."
codesign --force --sign - "$FRAMEWORKS_DIR/libonnxruntime.dylib"
codesign --force --sign - "$FRAMEWORKS_DIR/libsherpa-onnx-c-api.dylib"
codesign --force --deep --sign - "$APP_BUNDLE"

# 5. Verify bundle integrity & zero external non-system dependencies
echo "[5/5] Verifying Info.plist, signature, and binary portability..."
plutil -lint "$CONTENTS/Info.plist"
codesign -vvv --deep "$APP_BUNDLE"

BAD_DEPS=$(otool -L "$MACOS_DIR/$APP_NAME" "$FRAMEWORKS_DIR/libsherpa-onnx-c-api.dylib" "$FRAMEWORKS_DIR/libonnxruntime.dylib" | grep -E "/opt/homebrew|/usr/local|/Library/Frameworks/Python" || true)
if [ -n "$BAD_DEPS" ]; then
    echo "ERROR: Found non-portable external dylib dependencies:"
    echo "$BAD_DEPS"
    exit 1
fi

echo ""
echo "============================================================"
echo " SUCCESS! Portable offline bundle built at:"
echo " $APP_BUNDLE"
du -sh "$APP_BUNDLE"
echo "============================================================"
