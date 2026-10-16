#!/bin/bash
###############################################################################
#  Batocera Ports 启动器模板：dialog / TUI 类程序（BUA 的菜单就是这么修好的）
#
#  为什么要 xterm：从 ES 或桌面菜单启动的脚本**没有终端**，
#  dialog 之类会立刻退出（表现为"点了没反应"）。
###############################################################################
set -u
export DISPLAY="${DISPLAY:-:0.0}"
MENU="/userdata/system/add-ons/bua/menu.sh"     # ← 改成你的 TUI 脚本
exec xterm -T "Batocera Unofficial Add-Ons" -fa Monospace -fs 11 -geometry 110x34 \
     -e bash -c "bash '$MENU'; echo; echo '（已退出，按回车关闭窗口）'; read -r"
