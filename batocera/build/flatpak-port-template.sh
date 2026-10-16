#!/bin/bash
###############################################################################
#  Batocera Ports 启动器模板：flatpak 应用
#
#  用法：复制成 /userdata/roms/ports/<名字>.sh，改下面两行即可
#  为什么要这么写：
#    - Batocera 的 ES/桌面都以 root 运行，Electron/Chromium 类应用（Heroic、Steam…）
#      必须显式传 --no-sandbox，否则报 "Running as root without --no-sandbox is not supported"
#      （环境变量绕不过，只认命令行开关）
#    - flatpak 应用需要 session bus（否则 zypak-helper 报 Failed to connect to session bus）
#    - 日志统一落到 /userdata/system/logs/，排查方便
###############################################################################
set -u

APPNAME="Heroic"                              # ← 改成你的名字
APPID="com.heroicgameslauncher.hgl"           # ← 改成 flatpak 应用 id
EXTRA_ARGS="--no-sandbox"                     # Electron/Chromium 类必须；GTK 类应用留空

# 继承 ES 的环境（DISPLAY/audio 等都在里面）
export $(cat /proc/1/environ | tr '\0' '\n')
export DISPLAY="${DISPLAY:-:0.0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"

LOG="/userdata/system/logs/${APPNAME}.log"
mkdir -p "$(dirname "$LOG")"
echo "$(date): 启动 ${APPNAME} (${APPID})" >> "$LOG"

cd /userdata/system || exit 1

if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- flatpak run "$APPID" $EXTRA_ARGS "$@" >> "$LOG" 2>&1
else
    exec flatpak run "$APPID" $EXTRA_ARGS "$@" >> "$LOG" 2>&1
fi
