#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

# Explicitly invoked only. This script uploads the signed app to Apple.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/STILL.app}"
PROFILE="${NOTARY_PROFILE:-}"
if [ -z "$PROFILE" ]; then
    echo '请先配置 notarytool Keychain profile，再运行 NOTARY_PROFILE="配置名称" scripts/notarize.sh。' >&2
    exit 1
fi
if [ ! -d "$APP" ]; then echo "App 不存在：$APP" >&2; exit 1; fi
codesign --verify --deep --strict "$APP"
SIGNING_DETAILS="$(codesign -dvv "$APP" 2>&1)"
if [[ "$SIGNING_DETAILS" != *"Authority=Developer ID Application:"* ]]; then
    echo '必须先用 Developer ID Application 证书签名；ad-hoc 版本不可公证。' >&2
    exit 1
fi
mkdir -p "$ROOT/.build"
ARCHIVE="$ROOT/.build/STILL-notarization.zip"
RESULT="$ROOT/.build/notarization-result.plist"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
echo '向 Apple 上传并等待公证结果…'
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" --wait --output-format plist > "$RESULT"
STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$RESULT")"
if [ "$STATUS" != 'Accepted' ]; then
    echo "Apple 公证未通过：$STATUS。详情：$RESULT" >&2
    exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
"$ROOT/scripts/package.sh" "$APP"
echo '公证已通过并附加票据，ZIP/DMG 已重新生成。'
