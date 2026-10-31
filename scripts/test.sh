#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
mkdir -p "$BUILD/tests" "$BUILD/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD/module-cache"

# New files avoid stale executable/signature caches after recompilation on macOS.
rm -f "$BUILD/tests/app-tests" "$BUILD/tests/helper-tests" "$BUILD/tests/brightness-tests"
xcrun swiftc -swift-version 5 -Onone -parse-as-library -module-cache-path "$BUILD/module-cache" \
    "$ROOT/Sources/LidKeeper/PowerClient.swift" "$ROOT/Tests/AppTests/AppClientTests.swift" \
    -o "$BUILD/tests/app-tests" -framework Foundation -framework AppKit -framework IOKit
codesign --force --sign - "$BUILD/tests/app-tests"
"$BUILD/tests/app-tests"

xcrun swiftc -swift-version 5 -Onone -parse-as-library -module-cache-path "$BUILD/module-cache" \
    "$ROOT/Sources/LidKeeper/DisplayBrightness.swift" "$ROOT/Sources/LidKeeper/LidBrightnessController.swift" \
    "$ROOT/Tests/AppTests/BrightnessTests.swift" -o "$BUILD/tests/brightness-tests" \
    -framework Foundation -framework CoreGraphics -framework ColorSync -framework IOKit
codesign --force --sign - "$BUILD/tests/brightness-tests"
"$BUILD/tests/brightness-tests"

xcrun swiftc -swift-version 5 -Onone -parse-as-library -module-cache-path "$BUILD/module-cache" \
    "$ROOT/Sources/PowerHelper/SessionCore.swift" "$ROOT/Sources/PowerHelper/SecureFiles.swift" \
    "$ROOT/Sources/PowerHelper/SystemPower.swift" "$ROOT/Tests/HelperTests/HelperTests.swift" \
    -o "$BUILD/tests/helper-tests" -framework Foundation -framework IOKit
codesign --force --sign - "$BUILD/tests/helper-tests"
"$BUILD/tests/helper-tests"

bash -n "$ROOT/scripts/build.sh" "$ROOT/scripts/package.sh" "$ROOT/scripts/notarize.sh" "$ROOT/scripts/test.sh"
plutil -lint "$ROOT/Resources/Info.plist"
echo '逻辑与构建配置检查通过；真实合盖和首次管理员安装仍需在目标 Mac 验收。'
