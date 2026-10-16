#!/bin/bash
# Welkin - Batocera Ports launcher
# 直接使用自包含修复版 AppImage：GStreamer 插件 / libav / 环境修正都在包内
export DISPLAY=:0.0
export XDG_RUNTIME_DIR=/var/run
# Batocera 习惯：Escape 退出回 EmulationStation（桌面版不受影响）
export WELKIN_ESC_QUITS=1

pkill -f welkinplayer 2>/dev/null
sleep 1

LOG=/userdata/system/logs/welkin-app.log
[ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt 5000000 ] && mv -f "$LOG" "$LOG.1"

cd /userdata/system || exit 1
exec dbus-run-session -- ./Welkin_1.0.2_amd64-fixed.AppImage --no-sandbox >>"$LOG" 2>&1
