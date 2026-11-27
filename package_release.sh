#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

PLIST="$DIR/apps/TapticVoice/Sources/TapticVoice/Resources/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "0.2.0")

echo "Packaging TapticVoice Studio v${VERSION}..."
./apps/TapticVoice/build_app.sh

mkdir -p "$DIR/dist"
OUT_ZIP="$DIR/dist/TapticVoice-v${VERSION}-macOS.zip"
rm -f "$OUT_ZIP"

cd "$DIR/apps/TapticVoice/build"
ditto -c -k --sequesterRsrc --keepParent TapticVoice.app "$OUT_ZIP"

echo "Release archive ready: $OUT_ZIP"
ls -lh "$OUT_ZIP"
