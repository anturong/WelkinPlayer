#!/bin/bash
# Welkin - Batocera Ports launcher
# 自包含 AppImage：环境修正（去 libdbus、WebKit 软件路径、XDG_RUNTIME_DIR）已写进包内
# 新版播放由 rodio/symphonia 在 Rust 里解码，不需要 GStreamer 插件
export DISPLAY=:0.0
export XDG_RUNTIME_DIR=/var/run
# Batocera 习惯：Escape 退出回 EmulationStation（桌面版不受影响）
export WELKIN_ESC_QUITS=1
# 有可用的 3D 加速时取消下面这行的注释，让 WebKit 走硬件合成（帧率更高）
# export WELKIN_GL_ACCEL=1

pkill -f welkinplayer 2>/dev/null
sleep 1

LOG=/userdata/system/logs/welkin-app.log
[ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt 5000000 ] && mv -f "$LOG" "$LOG.1"

cd /userdata/system || exit 1
exec dbus-run-session -- ./Welkin_1.0.2_amd64-batocera.AppImage --no-sandbox >>"$LOG" 2>&1
