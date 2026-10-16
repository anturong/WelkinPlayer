#!/bin/bash
###############################################################################
#  把一个新编好的 welkinplayer 换进 AppImage，重新拼装成新的 AppImage
#
#  用法: bash swap-binary.sh <新二进制> <原AppImage> [输出AppImage]
#
#  说明: 只用 cp -a 摆平 AppDir，不用 mv —— 在 Batocera 上实测过 mv 会
#        "成功"但目标不出现，所以这里刻意避开它。
###############################################################################
set -eu

NEWBIN="${1:?用法: swap-binary.sh <新二进制> <原AppImage> [输出AppImage]}"
SRC="${2:?缺少原 AppImage}"
OUT="${3:-$(dirname "$SRC")/$(basename "${SRC%.AppImage}")-patched.AppImage}"

[ -f "$NEWBIN" ] || { echo "找不到新二进制: $NEWBIN" >&2; exit 1; }
[ -f "$SRC" ]    || { echo "找不到 AppImage: $SRC" >&2; exit 1; }
command -v mksquashfs >/dev/null || { echo "缺少 mksquashfs" >&2; exit 1; }

WORK="$(mktemp -d /tmp/welkin-swap.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "== 解包 $SRC =="
rm -rf squashfs-root appdir
"$SRC" --appimage-extract > /dev/null 2>&1
sync
[ -f squashfs-root/usr/bin/welkinplayer ] || { echo "解包失败：找不到 squashfs-root/usr/bin/welkinplayer" >&2; exit 1; }
mkdir -p appdir
cp -a squashfs-root/. appdir/
rm -rf squashfs-root

echo "== 替换二进制 =="
TARGET=appdir/usr/bin/welkinplayer
ls -l "$TARGET"
cp -f "$NEWBIN" "$TARGET"
chmod 755 "$TARGET"
ls -l "$TARGET"
sha256sum "$TARGET"

echo "== 重新拼装 =="
OFF=$("$SRC" --appimage-offset)
head -c "$OFF" "$SRC" > runtime.bin
mksquashfs appdir app.squashfs -comp zstd -noappend -no-progress -quiet
cat runtime.bin app.squashfs > "$OUT"
chmod 755 "$OUT"
echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"
"$OUT" --appimage-version | head -1
