#!/bin/bash
###############################################################################
#  在 Batocera 上把原始 Welkin AppImage 重新打包成「自包含修复版」
#
#  用法:
#      bash repack-welkin.sh <原始AppImage> <payload目录> [输出路径]
#
#  例:
#      bash repack-welkin.sh /userdata/system/Welkin_1.0.2_amd64.AppImage /tmp/payload
#      -> 输出 /userdata/system/Welkin_1.0.2_amd64-fixed.AppImage
#
#  payload 目录需包含（见 fetch-payload.py 生成）:
#      welkin_gst/      GStreamer 1.20.x 插件 + 扫描器 + libFLAC/liborc/libmpg123/gstrtp 等
#      welkin_ffmpeg/   libavcodec58 等 libav 运行时闭包
#
#  依赖: mksquashfs (Batocera 43.x 自带)
###############################################################################
set -eu

SRC="${1:?用法: repack-welkin.sh <原始AppImage> <payload目录> [输出路径]}"
PAYLOAD="${2:?缺少 payload 目录}"
OUT="${3:-$(dirname "$SRC")/$(basename "${SRC%.AppImage}")-fixed.AppImage}"

# 这些是「GStreamer 插件」，必须放进 usr/lib/gstreamer-1.0/
PLUGINS="libgstcoreelements.so libgstplayback.so libgsttypefindfunctions.so \
libgstaudioconvert.so libgstaudioresample.so libgstaudiorate.so libgstvolume.so \
libgstapp.so libgstpbtypes.so libgstalsa.so libgstautodetect.so libgstflac.so \
libgstaudioparsers.so libgstwavparse.so libgstid3demux.so libgstapetag.so \
libgstaudiofx.so libgstpulseaudio.so libgstmpg123.so libgstasf.so libgstlibav.so"

[ -f "$SRC" ]              || { echo "找不到 $SRC" >&2; exit 1; }
[ -d "$PAYLOAD/welkin_gst" ] || { echo "缺少 $PAYLOAD/welkin_gst" >&2; exit 1; }
command -v mksquashfs >/dev/null || { echo "缺少 mksquashfs" >&2; exit 1; }

WORK="$(mktemp -d /tmp/welkin-repack.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "== 1/6 解包原版 =="
"$SRC" --appimage-extract > /dev/null 2>&1
mv squashfs-root appdir

echo "== 2/6 放入 GStreamer 插件与扫描器 =="
mkdir -p appdir/usr/lib/gstreamer-1.0
n=0
for f in $PLUGINS; do
    if [ -f "$PAYLOAD/welkin_gst/$f" ]; then
        cp -f "$PAYLOAD/welkin_gst/$f" appdir/usr/lib/gstreamer-1.0/
        n=$((n + 1))
    fi
done
cp -f "$PAYLOAD/welkin_gst/gst-plugin-scanner" appdir/usr/lib/gstreamer-1.0/
chmod 755 appdir/usr/lib/gstreamer-1.0/gst-plugin-scanner
echo "   $n 个插件 + 扫描器"

echo "== 3/6 放入支撑库与 libav 运行时 =="
for f in "$PAYLOAD"/welkin_gst/*; do
    b="$(basename "$f")"
    case "$b" in
        libgst*.so|gst-plugin-scanner) continue ;;   # 插件已处理
        *) cp -f "$f" appdir/usr/lib/ ;;
    esac
done
if [ -d "$PAYLOAD/welkin_ffmpeg" ]; then
    cp -f "$PAYLOAD"/welkin_ffmpeg/* appdir/usr/lib/
fi
# 造出 soname 软链（libfoo.so.0 -> libfoo.so.0.2001.0）
cd appdir/usr/lib
for f in $(ls | grep -e '\.so\.[0-9]*\.' || true); do
    soname="$(echo "$f" | sed 's/\(.*\.so\.[0-9]*\)\..*/\1/')"
    [ "$f" = "$soname" ] || ln -sf "$f" "$soname"
done
cd "$WORK"

echo "== 4/6 移除自带的 libdbus（它会打崩系统 dbus-launch）=="
rm -f appdir/usr/lib/libdbus-1.so.3
echo "   已移除"

echo "== 5/6 写入 Batocera 适配（追加到会被 source 的 gtk 钩子）=="
cat >> appdir/apprun-hooks/linuxdeploy-plugin-gtk.sh <<'HOOKEOF'

# --- Batocera adaptation, appended during repack ---
# 无 3D 加速(VMware/无 render node)时 WebKit 必须走软件路径，否则白屏
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
# 包内插件目录的扫描器
: "${APPDIR:=$(dirname "$(realpath "$0")")}"
export GST_PLUGIN_SCANNER="$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner"
# 有内置 libav 后 decodebin 会抢用 avdec_mp3 导致 MP3 协商失败(not-negotiated)，
# 把实测可用的 mpg123 提到最高优先级
export GST_PLUGIN_FEATURE_RANK="mpg123audiodec:MAX"
# 音频(pipewire/pulse) 需要
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR=/var/run
fi
HOOKEOF

# AppRun 只按名字 source 那一个 gtk 钩子，这里额外挂上自己的钩子做双保险
cat > appdir/apprun-hooks/zz-welkin-fix.sh <<'HOOKEOF'
#! /bin/bash
: "${APPDIR:=$(dirname "$(realpath "$0")")}"
export GST_PLUGIN_SCANNER="$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner"
export GST_PLUGIN_FEATURE_RANK="mpg123audiodec:MAX"
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
HOOKEOF
chmod 755 appdir/apprun-hooks/zz-welkin-fix.sh
grep -q zz-welkin-fix appdir/AppRun || \
    sed -i 's|^exec "$this_dir"/AppRun.wrapped|source "$this_dir"/apprun-hooks/"zz-welkin-fix.sh"\nexec "$this_dir"/AppRun.wrapped|' appdir/AppRun

echo "== 6/6 重新拼装 AppImage =="
OFF=$("$SRC" --appimage-offset)
echo "   runtime offset = $OFF"
head -c "$OFF" "$SRC" > runtime.bin
mksquashfs appdir app.squashfs -comp zstd -noappend -no-progress -quiet
cat runtime.bin app.squashfs > "$OUT"
chmod 755 "$OUT"

echo
echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"
echo "自检: \"$OUT\" --appimage-version"
