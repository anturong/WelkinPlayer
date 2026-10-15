#!/bin/bash
###############################################################################
#  鍦?Batocera 涓婏紝鎶婃墦杩囪ˉ涓佺殑 welkinplayer 浜岃繘鍒舵浛鎹㈣繘淇鐗?AppImage
#
#  鐢ㄦ硶: bash swap-binary.sh <鏂颁簩杩涘埗> <鍘烝ppImage> [杈撳嚭AppImage]
###############################################################################
set -eu

NEWBIN="${1:?鐢ㄦ硶: swap-binary.sh <鏂颁簩杩涘埗> <鍘烝ppImage> [杈撳嚭]}"
SRC="${2:?缂哄皯鍘?AppImage}"
OUT="${3:-$(dirname "$SRC")/$(basename "${SRC%.AppImage}")-patched.AppImage}"

[ -f "$NEWBIN" ] || { echo "鎵句笉鍒版柊浜岃繘鍒? $NEWBIN" >&2; exit 1; }
[ -f "$SRC" ]    || { echo "鎵句笉鍒?AppImage: $SRC" >&2; exit 1; }
command -v mksquashfs >/dev/null || { echo "缂哄皯 mksquashfs" >&2; exit 1; }

WORK="$(mktemp -d /tmp/welkin-swap.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "== 瑙ｅ寘 $SRC =="
"$SRC" --appimage-extract > /dev/null 2>&1
mv squashfs-root appdir

echo "== 鏇挎崲浜岃繘鍒?=="
TARGET=appdir/usr/bin/welkinplayer
ls -l "$TARGET"
cp -f "$NEWBIN" "$TARGET"
chmod 755 "$TARGET"
ls -l "$TARGET"
sha256sum "$TARGET"

echo "== 閲嶆柊鎷艰 =="
OFF=$("$SRC" --appimage-offset)
head -c "$OFF" "$SRC" > runtime.bin
mksquashfs appdir app.squashfs -comp zstd -noappend -no-progress -quiet
cat runtime.bin app.squashfs > "$OUT"
chmod 755 "$OUT"
echo "瀹屾垚: $OUT ($(du -h "$OUT" | cut -f1))"
"$OUT" --appimage-version | head -1
