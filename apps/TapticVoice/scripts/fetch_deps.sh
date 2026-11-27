#!/bin/bash
# Fetches and prepares offline Sherpa-ONNX universal2 C-API runtime
# and bundled tiny int8 Persian & English Piper TTS models for TapticVoice.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$APP_ROOT/Vendor"
SHERPA_VERSION="v1.13.8"
SHERPA_ARCHIVE="sherpa-onnx-${SHERPA_VERSION}-osx-universal2-shared-lib.tar.bz2"
SHERPA_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/${SHERPA_ARCHIVE}"

FA_MODEL="vits-piper-fa_IR-amir-medium-int8"
EN_MODEL="vits-piper-en_US-amy-low-int8"
TTS_BASE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models"

mkdir -p "$VENDOR_DIR/sherpa-onnx" "$VENDOR_DIR/Models" "$VENDOR_DIR/tmp"
trap 'rm -rf "$VENDOR_DIR/tmp"' EXIT

# 1. Download & unpack Sherpa-ONNX universal2 C-API shared libraries
if [ ! -f "$VENDOR_DIR/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib" ]; then
    echo "[fetch_deps] Downloading ${SHERPA_ARCHIVE}..."
    curl -fsSL "$SHERPA_URL" -o "$VENDOR_DIR/tmp/${SHERPA_ARCHIVE}"
    tar -xjf "$VENDOR_DIR/tmp/${SHERPA_ARCHIVE}" -C "$VENDOR_DIR/tmp"
    EXTRACTED_DIR=$(find "$VENDOR_DIR/tmp" -maxdepth 1 -type d -name "sherpa-onnx-*" | head -n 1)
    rm -rf "$VENDOR_DIR/sherpa-onnx"
    mkdir -p "$VENDOR_DIR/sherpa-onnx"
    cp -R "$EXTRACTED_DIR/"* "$VENDOR_DIR/sherpa-onnx/"
    install_name_tool -change "@rpath/libonnxruntime.dylib" "@loader_path/libonnxruntime.dylib" "$VENDOR_DIR/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib"
    echo "[fetch_deps] Sherpa-ONNX installed in $VENDOR_DIR/sherpa-onnx"
else
    echo "[fetch_deps] Sherpa-ONNX runtime already cached."
fi

# 2. Download & extract tiny int8 Persian model
if [ ! -d "$VENDOR_DIR/Models/fa_IR" ]; then
    echo "[fetch_deps] Downloading ${FA_MODEL}.tar.bz2..."
    curl -fsSL "${TTS_BASE_URL}/${FA_MODEL}.tar.bz2" -o "$VENDOR_DIR/tmp/${FA_MODEL}.tar.bz2"
    tar -xjf "$VENDOR_DIR/tmp/${FA_MODEL}.tar.bz2" -C "$VENDOR_DIR/tmp"
    mv "$VENDOR_DIR/tmp/${FA_MODEL}" "$VENDOR_DIR/Models/fa_IR"
    # Move shared espeak-ng-data once to Models/espeak-ng-data
    if [ -d "$VENDOR_DIR/Models/fa_IR/espeak-ng-data" ] && [ ! -d "$VENDOR_DIR/Models/espeak-ng-data" ]; then
        mv "$VENDOR_DIR/Models/fa_IR/espeak-ng-data" "$VENDOR_DIR/Models/espeak-ng-data"
    else
        rm -rf "$VENDOR_DIR/Models/fa_IR/espeak-ng-data"
    fi
else
    echo "[fetch_deps] Bundled fa_IR model already cached."
fi

# 3. Download & extract tiny int8 English model
if [ ! -d "$VENDOR_DIR/Models/en_US" ]; then
    echo "[fetch_deps] Downloading ${EN_MODEL}.tar.bz2..."
    curl -fsSL "${TTS_BASE_URL}/${EN_MODEL}.tar.bz2" -o "$VENDOR_DIR/tmp/${EN_MODEL}.tar.bz2"
    tar -xjf "$VENDOR_DIR/tmp/${EN_MODEL}.tar.bz2" -C "$VENDOR_DIR/tmp"
    mv "$VENDOR_DIR/tmp/${EN_MODEL}" "$VENDOR_DIR/Models/en_US"
    if [ -d "$VENDOR_DIR/Models/en_US/espeak-ng-data" ] && [ ! -d "$VENDOR_DIR/Models/espeak-ng-data" ]; then
        mv "$VENDOR_DIR/Models/en_US/espeak-ng-data" "$VENDOR_DIR/Models/espeak-ng-data"
    else
        rm -rf "$VENDOR_DIR/Models/en_US/espeak-ng-data"
    fi
else
    echo "[fetch_deps] Bundled en_US model already cached."
fi

echo "[fetch_deps] Done! Contents of Vendor/:"
ls -lh "$VENDOR_DIR/sherpa-onnx/lib"
ls -lh "$VENDOR_DIR/Models/fa_IR" "$VENDOR_DIR/Models/en_US"
du -sh "$VENDOR_DIR/Models" "$VENDOR_DIR/sherpa-onnx"
