#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "Packaging TapticVoice Release..."
./apps/TapticVoice/build_app.sh

mkdir -p dist
cd apps/TapticVoice/build
ditto -c -k --sequesterRsrc --keepParent TapticVoice.app "$DIR/dist/TapticVoice-macOS.zip"

echo "Release package created: $DIR/dist/TapticVoice-macOS.zip"
ls -lh "$DIR/dist/TapticVoice-macOS.zip"
