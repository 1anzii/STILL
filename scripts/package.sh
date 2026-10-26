#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/STILL.app}"
if [ ! -d "$APP" ]; then echo "未找到 App，请先运行 scripts/build.sh：$APP" >&2; exit 1; fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHS_ACTUAL="$(xcrun lipo -archs "$APP/Contents/MacOS/LidKeeper")"
if [[ "$ARCHS_ACTUAL" == *arm64* && "$ARCHS_ACTUAL" == *x86_64* ]]; then FLAVOR=universal; else FLAVOR="${ARCHS_ACTUAL// /-}"; fi
STAGE="$ROOT/.build/dmg-stage"
DIST="$ROOT/dist"
BASE="$DIST/STILL-$VERSION-$FLAVOR"
mkdir -p "$DIST"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BASE.zip"
echo "ZIP：$BASE.zip"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/STILL.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/安装说明.txt" "$STAGE/安装说明.txt"
hdiutil create -volname 'STILL' -srcfolder "$STAGE" -ov -fs HFS+ -format UDZO "$BASE.dmg"
echo "DMG：$BASE.dmg"
(cd "$DIST" && shasum -a 256 "$(basename "$BASE.zip")" "$(basename "$BASE.dmg")" > "$(basename "$BASE")-SHA256.txt")
echo "校验值：$BASE-SHA256.txt"

