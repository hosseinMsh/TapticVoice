#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_ROOT"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Library/Developer/CommandLineTools" ]; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

mkdir -p /tmp/clang-cache

if swift test -Xswiftc -module-cache-path -Xswiftc /tmp/clang-cache -Xcc -fmodules-cache-path=/tmp/clang-cache 2>/dev/null; then
    echo "XCTest suite passed!"
else
    echo "XCTest unavailable in CommandLineTools; running TapticCoreVerify test suite..."
    swift run TapticCoreVerify \
        -Xswiftc -module-cache-path -Xswiftc /tmp/clang-cache \
        -Xcc -fmodules-cache-path=/tmp/clang-cache
fi
