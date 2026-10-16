#!/bin/bash
###############################################################################
#  把上游原始 Welkin AppImage 重新打包成「可用于 Batocera 的版本」
#
#  用法:
#      bash repack-welkin.sh <原始AppImage> [payload目录|-] [输出路径]
#
#  例:
#      bash repack-welkin.sh Welkin_1.0.2_amd64.AppImage - /tmp/Welkin-fixed.AppImage
#
#  payload 目录是**可选**的：新版播放由 rodio/symphonia 在 Rust 里解码，
#  不再经过 webview 的 GStreamer，所以正常情况下不需要任何插件闭包。
#  仅当上游还在用「webview + GStreamer」的旧架构时才需要传入（见 fetch-payload.py）：
#      welkin_gst/      GStreamer 插件 + 扫描器
#      welkin_ffmpeg/   libavcodec58 等 libav 运行时闭包
#
#  依赖: mksquashfs (Batocera 43.x 自带)
###############################################################################
set -eu

SRC="${1:?用法: repack-welkin.sh <原始AppImage> [payload目录|-] [输出路径]}"
PAYLOAD="${2:--}"
OUT="${3:-$(dirname "$SRC")/$(basename "${SRC%.AppImage}")-fixed.AppImage}"

# 这些是「GStreamer 插件」，必须放进 usr/lib/gstreamer-1.0/（仅旧架构需要）
PLUGINS="libgstcoreelements.so libgstplayback.so libgsttypefindfunctions.so \
libgstaudioconvert.so libgstaudioresample.so libgstaudiorate.so libgstvolume.so \
libgstapp.so libgstpbtypes.so libgstalsa.so libgstautodetect.so libgstflac.so \
libgstaudioparsers.so libgstwavparse.so libgstid3demux.so libgstapetag.so \
libgstaudiofx.so libgstpulseaudio.so libgstmpg123.so libgstasf.so libgstlibav.so"

[ -f "$SRC" ] || { echo "找不到 $SRC" >&2; exit 1; }
command -v mksquashfs >/dev/null || { echo "缺少 mksquashfs" >&2; exit 1; }

HAVE_PAYLOAD=0
if [ "$PAYLOAD" != "-" ] && [ -d "$PAYLOAD/welkin_gst" ]; then
    HAVE_PAYLOAD=1
else
    echo "== payload 未提供：新架构（rodio/symphonia）不需要 GStreamer/libav 闭包 =="
fi

WORK="$(mktemp -d /tmp/welkin-repack.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "== 1/6 解包原版 =="
"$SRC" --appimage-extract > /dev/null 2>&1
mv squashfs-root appdir

if [ "$HAVE_PAYLOAD" = 1 ]; then
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
    shopt -s nullglob
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
    shopt -u nullglob
    # 造出 soname 软链（libfoo.so.0 -> libfoo.so.0.2001.0）
    cd appdir/usr/lib
    for f in $(ls | grep -e '\.so\.[0-9]*\.' || true); do
        soname="$(echo "$f" | sed 's/\(.*\.so\.[0-9]*\)\..*/\1/')"
        [ "$f" = "$soname" ] || ln -sf "$f" "$soname"
    done
    cd "$WORK"
else
    echo "== 2-3/6 跳过 payload =="
fi

echo "== 4/6 移除自带的 libdbus（它会打崩系统 dbus-launch）=="
rm -f appdir/usr/lib/libdbus-1.so.3
echo "   已移除"

echo "== 5/6 写入 Batocera 适配（追加到会被 source 的 gtk 钩子）=="
cat >> appdir/apprun-hooks/linuxdeploy-plugin-gtk.sh <<'HOOKEOF'

# --- Batocera adaptation, appended during repack ---
# 无 3D 加速（VM／没有 render node）时 WebKit 必须走软件路径，否则白屏。
# 真机有可用 GPU 时，在启动器里设 WELKIN_GL_ACCEL=1 即可恢复硬件合成。
if [ "${WELKIN_GL_ACCEL:-0}" != "1" ]; then
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
    export WEBKIT_DISABLE_COMPOSITING_MODE=1
fi
: "${APPDIR:=$(dirname "$(realpath "$0")")}"
# GStreamer 扫描器只在包内确实带了插件时才有意义
if [ -d "$APPDIR/usr/lib/gstreamer-1.0" ]; then
    export GST_PLUGIN_SCANNER="$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner"
    # 有内置 libav 后 decodebin 会抢用 avdec_mp3 导致 MP3 协商失败(not-negotiated)，
    # 把实测可用的 mpg123 提到最高优先级
    export GST_PLUGIN_FEATURE_RANK="mpg123audiodec:MAX"
fi
# 音频(pipewire/pulse) 需要
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR=/var/run
fi
HOOKEOF

# AppRun 只按名字 source 那一个 gtk 钩子，这里额外挂上自己的钩子做双保险
cat > appdir/apprun-hooks/zz-welkin-fix.sh <<'HOOKEOF'
#! /bin/bash
: "${APPDIR:=$(dirname "$(realpath "$0")")}"
if [ "${WELKIN_GL_ACCEL:-0}" != "1" ]; then
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
    export WEBKIT_DISABLE_COMPOSITING_MODE=1
fi
if [ -d "$APPDIR/usr/lib/gstreamer-1.0" ]; then
    export GST_PLUGIN_SCANNER="$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner"
    export GST_PLUGIN_FEATURE_RANK="mpg123audiodec:MAX"
fi
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR=/var/run
fi
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
