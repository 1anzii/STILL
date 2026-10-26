#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAL_BUILD="$ROOT/.build/dial-tests"
DIAL_MODULE_CACHE="$ROOT/.build/module-cache"
mkdir -p "$DIAL_BUILD" "$DIAL_MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$DIAL_MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="$DIAL_MODULE_CACHE"

# A new executable inode avoids macOS retaining a previous ad-hoc signature.
rm -f "$DIAL_BUILD/rotary-dial-tests"
xcrun swiftc -swift-version 5 -Onone -parse-as-library \
    -module-cache-path "$DIAL_MODULE_CACHE" \
    "$ROOT/Sources/LidKeeper/RotaryDial.swift" "$ROOT/Tests/RotaryDialTests.swift" \
    -o "$DIAL_BUILD/rotary-dial-tests" -framework Foundation
codesign --force --sign - "$DIAL_BUILD/rotary-dial-tests"
"$DIAL_BUILD/rotary-dial-tests"
bash -n "$ROOT/scripts/test-dial.sh"
