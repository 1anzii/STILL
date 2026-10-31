#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

# Export only reviewed source inputs; never copy the working tree recursively.
set -euo pipefail
umask 022
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { echo "源码导出失败：$1" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || fail '需要 Python 3 生成兼容 UTF-8 文件名的源码 ZIP。'

files=(
    README.md LICENSE THIRD_PARTY_NOTICES.md PUBLISHING.md .gitignore
    docs/DEVELOPMENT.md docs/images/still-overview.png
    Sources/PowerHelper/PROTOCOL.md
    Resources/Info.plist Resources/AppIcon.png Resources/AppIcon.icns Resources/安装说明.txt
    Resources/Fonts/Michroma-Regular.ttf Resources/Fonts/OFL.txt Resources/Fonts/SOURCE.txt
    Resources/Textures/WornYellowMetal-v1.png Resources/Textures/SOURCE.md
    scripts/build.sh scripts/package.sh scripts/notarize.sh scripts/generate-icon.swift
    scripts/test.sh scripts/test-dial.sh scripts/test-switch.sh scripts/export-source.sh
)
required=("${files[@]}"
    Sources/LidKeeper/AppMain.swift Sources/LidKeeper/Brand.swift
    Sources/LidKeeper/BrandWordmark.swift Sources/LidKeeper/EngravedSettingsIcon.swift
    Sources/LidKeeper/MachineLabel.swift Sources/LidKeeper/PanelStatus.swift
    Sources/LidKeeper/PanelView.swift Sources/LidKeeper/PowerClient.swift
    Sources/LidKeeper/RotaryDial.swift Sources/LidKeeper/RunSwitch.swift
    Sources/LidKeeper/SleepModel.swift Sources/LidKeeper/StatusPanel.swift
    Sources/PowerHelper/HelperMain.swift Sources/PowerHelper/SecureFiles.swift
    Sources/PowerHelper/SessionCore.swift Sources/PowerHelper/SystemPower.swift
    Tests/RotaryDialTests.swift Tests/RunSwitchTests.swift Tests/LidProbe.swift
    Tests/AppTests/AppClientTests.swift Tests/HelperTests/HelperTests.swift
)

regular_file() {
    local relative="$1" part="$1"
    case "$relative" in
        /*|../*|*/../*|*/..|*$'\n'*|*$'\r'*|*$'\t'*) fail '白名单中存在不安全路径。' ;;
    esac
    # Reject linked files and linked ancestors, even if they point inside ROOT.
    while :; do
        [ ! -L "$ROOT/$part" ] || fail '白名单文件或其父目录是符号链接。'
        [[ "$part" == */* ]] || break
        part="${part%/*}"
    done
    [ -f "$ROOT/$relative" ] || fail "缺少必需文件：$relative"
}
for relative in "${required[@]}"; do regular_file "$relative"; done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Info.plist 版本必须为 x.y.z。'
DIST="$ROOT/dist"
TARGET="$DIST/open-source-$VERSION"
ARCHIVE="$DIST/STILL-$VERSION-source.zip"
[ ! -L "$DIST" ] || fail 'dist 不能是符号链接。'
for output in "$TARGET" "$ARCHIVE"; do
    [ ! -e "$output" ] && [ ! -L "$output" ] || fail '目标已存在；请先选择新版本或另行移走旧导出。'
done
mkdir -p "$DIST"
stage="$(mktemp -d "$DIST/.source-export.XXXXXX")"
target_created=0
finished=0
cleanup() {
    rm -rf "$stage"
    if [ "$finished" -eq 0 ] && [ "$target_created" -eq 1 ]; then rm -rf "$TARGET"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Capture find's status before consuming its output: process substitution
# would otherwise hide a failed traversal and allow an incomplete export.
if ! /usr/bin/find "$ROOT/Sources" -type f -name '*.swift' -print0 > "$stage/sources.list" 2>/dev/null; then
    fail '无法完整遍历 Sources，未导出源码。'
fi
while IFS= read -r -d '' source; do files+=("${source#"$ROOT/"}"); done < "$stage/sources.list"
# Tests include only direct Swift files in these known locations, never logs.
shopt -s nullglob
for source in "$ROOT"/Tests/*.swift "$ROOT"/Tests/AppTests/*.swift "$ROOT"/Tests/HelperTests/*.swift; do
    files+=("${source#"$ROOT/"}")
done
shopt -u nullglob
for relative in "${files[@]}"; do regular_file "$relative"; done

mkdir "$stage/STILL"
for relative in "${files[@]}"; do
    mkdir -p "$stage/STILL/$(dirname "$relative")"
    # -X omits resource forks and extended attributes from the source export.
    cp -X "$ROOT/$relative" "$stage/STILL/$relative"
    case "$relative" in scripts/*.sh) chmod 755 "$stage/STILL/$relative" ;; *) chmod 644 "$stage/STILL/$relative" ;; esac
done
for relative in "${required[@]}"; do
    [ -f "$stage/STILL/$relative" ] && [ ! -L "$stage/STILL/$relative" ] || fail "副本缺少必需文件：$relative"
done

# Inspect the copied bytes. Emit no matching content, credentials, or local
# paths. Split literal prefixes so this scanner does not match its own source.
local_paths='/'"Users/[^/[:space:]]+"
local_paths+='|/'"home/[^/[:space:]]+"
local_paths+='|/'"private/var/"'folders/'
local_paths+='|/'"var/folders/"
local_paths+='|[A-Za-z]:\\Users\\'
for relative in "${files[@]}"; do
    lower="$(printf '%s' "$relative" | tr '[:upper:]' '[:lower:]')"
    case "/$lower" in
        */.git/*|*/.build/*|*/dist/*|*/.ssh/*|*/.aws/*|*/.codex/*|*/.agents/*|*/keys/*|*/secrets/*|*/private/*)
            fail '检测到禁止导出的目录名。' ;;
    esac
    case "${lower##*/}" in
        .env|.env.*|*.key|*.pem|*.p12|*.pfx|*.cer|*.crt|*.mobileprovision|*.provisionprofile|*.keychain*|id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*|*secret*|*credential*|*password*|*token*|*.log|*.jsonl|*.m4a|*.wav|*.mp3)
            fail '检测到密钥、凭据或私人记录的高风险文件名。' ;;
    esac
    if LC_ALL=C /usr/bin/grep -I -q -E "$local_paths" "$stage/STILL/$relative"; then
        fail '检测到本机个人目录路径；请清理源码后重新导出。'
    else
        result=$?
        [ "$result" -eq 1 ] || fail '无法完成本地路径检查。'
    fi
done
python3 - "$stage" <<'PY'
from pathlib import Path
import sys
import zipfile

stage = Path(sys.argv[1])
with zipfile.ZipFile(stage / "archive.zip", "x", compression=zipfile.ZIP_DEFLATED,
                     compresslevel=9) as archive:
    for path in sorted((stage / "STILL").rglob("*")):
        relative = path.relative_to(stage)
        if ".git" in relative.parts or path.name == ".DS_Store":
            continue
        if path.is_symlink():
            raise SystemExit("源码副本中存在符号链接，未导出 ZIP。")
        if path.is_file():
            # zipfile marks non-ASCII names as UTF-8 and retains Unix modes,
            # including the 0755 permissions set on shell scripts above.
            archive.write(path, arcname=relative.as_posix())
PY

# mkdir and hard-link creation both refuse existing names, including races
# after the initial checks. Publish only after validation and ZIP creation.
mkdir "$TARGET" || fail '源码目标已存在，未覆盖。'
target_created=1
mv "$stage/STILL" "$TARGET/STILL"
ln "$stage/archive.zip" "$ARCHIVE" || fail 'ZIP 目标已存在，未覆盖。'
finished=1
echo "源码导出完成：${#files[@]} 个文件；本地路径与高风险文件名检查通过。"
echo "源码目录：$TARGET/STILL"
echo "源码 ZIP：$ARCHIVE"
