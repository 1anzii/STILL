#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
DIST="$ROOT/dist"
APP="$BUILD/app-stage/STILL.app"
FINAL_APP="$DIST/STILL.app"
VERSION="${APP_VERSION:-1.10.0}"
BUILD_NUMBER="${APP_BUILD:-24}"
IDENTITY="${SIGN_IDENTITY:--}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCHITECTURES=(arm64 x86_64)
if [ -n "${ARCHS:-}" ]; then read -r -a ARCHITECTURES <<< "$ARCHS"; fi
if [ "${#ARCHITECTURES[@]}" -eq 0 ]; then echo 'ARCHS must contain arm64 and/or x86_64.' >&2; exit 1; fi
for architecture in "${ARCHITECTURES[@]}"; do
    case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;; esac
done
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo 'APP_VERSION must be x.y.z and APP_BUILD must be an integer.' >&2
    exit 1
fi

mkdir -p "$BUILD/tools" "$BUILD/module-cache" "$DIST"
export CLANG_MODULE_CACHE_PATH="$BUILD/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD/module-cache"
echo '绘制应用图标…'
xcrun swiftc -module-cache-path "$BUILD/module-cache" "$ROOT/scripts/generate-icon.swift" -o "$BUILD/tools/generate-icon" -framework AppKit -framework CoreText
"$BUILD/tools/generate-icon" "$ROOT/Resources"

app_binaries=()
helper_binaries=()
for architecture in "${ARCHITECTURES[@]}"; do
    echo "编译 ${architecture}（macOS 13+）…"
    mkdir -p "$BUILD/$architecture"
    rm -f "$BUILD/$architecture/LidKeeper" "$BUILD/$architecture/com.yeonza.LidKeeper.helper"
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -parse-as-library \
        -module-cache-path "$BUILD/module-cache" -sdk "$SDK" -target "$architecture-apple-macos13.0" \
        "$ROOT"/Sources/LidKeeper/*.swift -o "$BUILD/$architecture/LidKeeper" \
        -framework AppKit -framework SwiftUI -framework Foundation -framework IOKit -framework ServiceManagement -framework Security -framework CoreText -framework CoreGraphics -framework ColorSync
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -parse-as-library \
        -module-cache-path "$BUILD/module-cache" -sdk "$SDK" -target "$architecture-apple-macos13.0" \
        "$ROOT"/Sources/PowerHelper/*.swift -o "$BUILD/$architecture/com.yeonza.LidKeeper.helper" \
        -framework Foundation -framework IOKit -framework Security
    app_binaries+=("$BUILD/$architecture/LidKeeper")
    helper_binaries+=("$BUILD/$architecture/com.yeonza.LidKeeper.helper")
done

# Sign a staging bundle first, then copy its final bytes into a fresh bundle.
# This avoids executable vnode/signature caches from in-place re-signing.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchServices"
xcrun lipo -create "${app_binaries[@]}" -output "$APP/Contents/MacOS/LidKeeper"
xcrun lipo -create "${helper_binaries[@]}" -output "$APP/Contents/Library/LaunchServices/com.yeonza.LidKeeper.helper"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
ditto "$ROOT/Resources/Fonts" "$APP/Contents/Resources/Fonts"
ditto "$ROOT/Resources/Textures" "$APP/Contents/Resources/Textures"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
if [ -f "$ROOT/Resources/安装说明.txt" ]; then cp "$ROOT/Resources/安装说明.txt" "$APP/Contents/Resources/安装说明.txt"; fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/LidKeeper" "$APP/Contents/Library/LaunchServices/com.yeonza.LidKeeper.helper"

sign_args=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != '-' ]; then sign_args+=(--options runtime --timestamp); fi
codesign "${sign_args[@]}" --identifier com.yeonza.LidKeeper.helper "$APP/Contents/Library/LaunchServices/com.yeonza.LidKeeper.helper"
codesign "${sign_args[@]}" "$APP"
# Only replace this project's generated app, never the rest of dist/.
rm -rf "$FINAL_APP"
ditto "$APP" "$FINAL_APP"
codesign --verify --deep --strict --verbose=2 "$FINAL_APP"
plutil -lint "$FINAL_APP/Contents/Info.plist"
echo "构建完成：$FINAL_APP"
xcrun lipo -info "$FINAL_APP/Contents/MacOS/LidKeeper"
xcrun lipo -info "$FINAL_APP/Contents/Library/LaunchServices/com.yeonza.LidKeeper.helper"
if [ "$IDENTITY" = '-' ]; then echo '当前为 ad-hoc 签名，未公证；给同事使用时可能需要在系统设置中允许打开。'; fi

