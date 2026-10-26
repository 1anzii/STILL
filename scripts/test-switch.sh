#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWITCH_BUILD="$ROOT/.build/switch-tests"
SWITCH_MODULE_CACHE="$ROOT/.build/module-cache"
mkdir -p "$SWITCH_BUILD" "$SWITCH_MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$SWITCH_MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="$SWITCH_MODULE_CACHE"

# A new executable inode avoids macOS retaining a previous ad-hoc signature.
rm -f "$SWITCH_BUILD/run-switch-tests"
xcrun swiftc -swift-version 5 -Onone -parse-as-library \
    -module-cache-path "$SWITCH_MODULE_CACHE" \
    "$ROOT/Sources/LidKeeper/RunSwitch.swift" "$ROOT/Sources/LidKeeper/PanelStatus.swift" \
    "$ROOT/Tests/RunSwitchTests.swift" \
    -o "$SWITCH_BUILD/run-switch-tests"
codesign --force --sign - "$SWITCH_BUILD/run-switch-tests"
"$SWITCH_BUILD/run-switch-tests"
bash -n "$ROOT/scripts/test-switch.sh"
