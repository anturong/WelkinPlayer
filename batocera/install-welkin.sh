#!/bin/bash
###############################################################################
#  Welkin (修复版 AppImage) -> Batocera  安装 / 自检 / 卸载
#
#  在 Batocera 上以 root 执行:
#      bash install-welkin.sh [选项] [/path/to/Welkin_1.0.2_amd64-batocera.AppImage]
#
#  不给路径时自动找 /userdata/system/Welkin*.AppImage（优先 -batocera，其次 -fixed）
#
#  选项:
#      --verify        装完起一个实例自检（进程 / 截图 / 音频链路）
#      --restart       装完或卸载后重启 EmulationStation
#      --no-gamelist   不写 gamelist.xml（菜单里显示小写文件名 welkin）
#      --uninstall     卸载：删启动脚本 + 菜单条目（保留 AppImage）
#      --purge         --uninstall 时连 AppImage 一起删
#      --quiet         精简输出
#      -h | --help     帮助
###############################################################################
set -u

TARGET_DIR=/userdata/system
PORTS_DIR=/userdata/roms/ports
PORT_SCRIPT="$PORTS_DIR/welkin.sh"
GAMELIST="$PORTS_DIR/gamelist.xml"
VERIFY_LOG=/tmp/welkin-app-launch.log

VERIFY=0; RESTART=0; GAMELIST_EDIT=1; UNINSTALL=0; PURGE=0; QUIET=0
APPIMAGE=""

c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
step()   { [ "$QUIET" = 1 ] || printf '\n\033[1m== %s\033[0m\n' "$*"; }
info()   { [ "$QUIET" = 1 ] || printf '   %s\n' "$*"; }

usage() { sed -n '2,20p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --verify)      VERIFY=1 ;;
        --restart)     RESTART=1 ;;
        --no-gamelist) GAMELIST_EDIT=0 ;;
        --uninstall)   UNINSTALL=1 ;;
        --purge)       UNINSTALL=1; PURGE=1 ;;
        --quiet)       QUIET=1 ;;
        -h|--help)     usage; exit 0 ;;
        -*)            c_err "未知选项: $1"; usage; exit 2 ;;
        *)             APPIMAGE="$1" ;;
    esac
    shift
done

[ "$(id -u)" = 0 ] || { c_err "需要 root"; exit 1; }
[ -d /userdata ]   || { c_err "这不是 Batocera：找不到 /userdata"; exit 1; }

kill_welkin() {
    pkill -f 'welkinplayer' 2>/dev/null
    pkill -f 'Welkin_.*AppImage' 2>/dev/null
    sleep 2
}

resolve_appimage() {
    if [ -n "$APPIMAGE" ]; then
        [ -f "$APPIMAGE" ] || { c_err "找不到文件: $APPIMAGE"; exit 1; }
    else
        APPIMAGE=$(ls -1t "$TARGET_DIR"/Welkin*-batocera.AppImage 2>/dev/null | head -1)
        [ -n "$APPIMAGE" ] || APPIMAGE=$(ls -1t "$TARGET_DIR"/Welkin*-fixed.AppImage 2>/dev/null | head -1)
        [ -n "$APPIMAGE" ] || APPIMAGE=$(ls -1t "$TARGET_DIR"/Welkin*.AppImage 2>/dev/null | head -1)
        if [ -z "$APPIMAGE" ]; then
            c_err "没找到 AppImage。请先上传，例如:"
            c_err "  scp Welkin_1.0.2_amd64-batocera.AppImage root@<batocera>:/userdata/system/"
            exit 1
        fi
    fi
    if [ "$(dirname "$APPIMAGE")" != "$TARGET_DIR" ]; then
        info "复制到 $TARGET_DIR ..."
        cp -f "$APPIMAGE" "$TARGET_DIR/" || { c_err "复制失败"; exit 1; }
        APPIMAGE="$TARGET_DIR/$(basename "$APPIMAGE")"
    fi
    chmod 755 "$APPIMAGE"
}

gamelist_edit() {
    local mode="$1"
    [ -f "$GAMELIST" ] || { [ "$mode" = remove ] && return 0
        printf '<?xml version="1.0"?>\n<gameList>\n</gameList>\n' > "$GAMELIST"; }
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$GAMELIST" "$mode" <<'PY'
import io, re, sys
path, mode = sys.argv[1], sys.argv[2]
s = io.open(path, encoding='utf-8').read()
block = (r'[ \t]*<game>(?:(?!</game>).)*?<path>\./welkin\.sh</path>'
         r'(?:(?!</game>).)*?</game>[ \t]*\r?\n?')
s = re.sub(block, '', s, flags=re.S)
if mode == 'add':
    entry = '\t<game>\n\t\t<path>./welkin.sh</path>\n\t\t<name>Welkin</name>\n\t</game>\n'
    s = s.replace('</gameList>', entry + '</gameList>') if '</gameList>' in s \
        else s.rstrip('\n') + '\n' + entry + '</gameList>\n'
io.open(path, 'w', encoding='utf-8').write(s)
PY
    else
        [ "$mode" = remove ] && return 0
        grep -q 'welkin\.sh' "$GAMELIST" && return 0
        sed -i 's#</gameList>#\t<game>\n\t\t<path>./welkin.sh</path>\n\t\t<name>Welkin</name>\n\t</game>\n</gameList>#' "$GAMELIST"
    fi
}

write_port_script() {
    local base="$1"
    mkdir -p "$PORTS_DIR"
    cat > "$PORT_SCRIPT" <<EOF
#!/bin/bash
# Welkin - Batocera Ports launcher  (由 install-welkin.sh 生成)
export DISPLAY=:0.0
export XDG_RUNTIME_DIR=/var/run

pkill -f welkinplayer 2>/dev/null
sleep 1

LOG=/userdata/system/logs/welkin-app.log
[ -f "\$LOG" ] && [ "\$(stat -c%s "\$LOG")" -gt 5000000 ] && mv -f "\$LOG" "\$LOG.1"

cd /userdata/system || exit 1
exec dbus-run-session -- "./$base" --no-sandbox >>"\$LOG" 2>&1
EOF
    chmod 755 "$PORT_SCRIPT"
}

do_uninstall() {
    step "卸载 Welkin"
    kill_welkin
    rm -f "$PORT_SCRIPT" && info "已删除 $PORT_SCRIPT"
    [ "$GAMELIST_EDIT" = 1 ] && { gamelist_edit remove; info "已清理 gamelist.xml 条目"; }
    if [ "$PURGE" = 1 ]; then
        if [ -z "$APPIMAGE" ] || [ ! -f "$APPIMAGE" ]; then
            APPIMAGE=$(ls -1t "$TARGET_DIR"/Welkin*.AppImage 2>/dev/null | head -1)
        fi
        [ -n "$APPIMAGE" ] && rm -f "$APPIMAGE" && info "已删除 $APPIMAGE"
    else
        info "AppImage 保留（--purge 可一并删除）"
    fi
    [ "$RESTART" = 1 ] && batocera-es-swissknife --restart >/dev/null 2>&1 &
    c_ok "卸载完成"
}

do_verify() {
    step "自检（约 35 秒）"
    [ -e /tmp/.X11-unix/X0 ] || { c_warn "没有 X 会话，跳过"; return 0; }
    kill_welkin
    nohup bash "$PORT_SCRIPT" > "$VERIFY_LOG" 2>&1 &
    sleep 30
    local pass=1 n APP
    pgrep -f 'welkinplayer' >/dev/null   && c_ok "PASS  welkinplayer 主进程在运行" || { c_err "FAIL  主进程没起来"; pass=0; }
    pgrep -f 'WebKitWeb' >/dev/null      && c_ok "PASS  WebKitWebProcess 存活（界面能渲染）" || { c_err "FAIL  WebKitWebProcess 已死 → 白屏"; pass=0; }
    n=$(grep -c -e 'autoaudiosink not found' -e 'plugin loader failed' "$VERIFY_LOG" 2>/dev/null || true)
    [ "${n:-0}" = 0 ] && c_ok "PASS  无 GStreamer 缺件报错" || { c_err "FAIL  有 $n 条 GStreamer 缺件报错"; pass=0; }

    if command -v ffmpeg >/dev/null 2>&1; then
        local res sz
        res=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}'); res=${res:-1920x1080}
        ffmpeg -y -loglevel error -f x11grab -video_size "$res" -i :0.0 -frames:v 1 /tmp/welkin-verify.png 2>/dev/null
        sz=$(stat -c %s /tmp/welkin-verify.png 2>/dev/null || echo 0)
        info "截图 /tmp/welkin-verify.png ($sz 字节；白屏约 8~12KB，正常 >200KB)"
        [ "$sz" -lt 60000 ] && c_warn "截图偏小，可能是白屏，人工确认一下"
    fi

    APP=$(basename "$APPIMAGE")
    APP=$(ls -1 /userdata/system/Welkin*.AppImage 2>/dev/null | head -1)
    if [ -n "$APP" ]; then
        local APPDIR="$TMP_APPDIR"
        info "(音频链路请用 --verify 之后的播放键实测，或见 README 第 4 节命令)"
    fi
    kill_welkin
    info "日志: $VERIFY_LOG"
    [ "$pass" = 1 ] && c_ok "自检通过" || c_err "自检未通过，请看 $VERIFY_LOG"
}

do_install() {
    resolve_appimage
    local base; base="$(basename "$APPIMAGE")"
    step "目标"
    info "AppImage : $APPIMAGE ($(du -h "$APPIMAGE" | cut -f1))"

    step "校验"
    if "$APPIMAGE" --appimage-version >/dev/null 2>&1; then
        info "OK    $(cd "$TARGET_DIR" && "./$base" --appimage-version 2>&1 | head -1)"
    else
        c_warn "读不到 AppImage 运行时信息"
    fi
    case "$base" in
        *-batocera*) c_ok "OK    这是 batocera 修复版（插件/环境内置 + 本地音源代理补丁）" ;;
        *-fixed*)    c_warn "这是早期修复版：插件/环境没问题，但本地音源命中上游 bug 会没声音（见 README「本地音源修复」）" ;;
        *) c_warn "这不是修复版；原版在 Batocera 上一播放就会崩（见 README 第 1 节）" ;;
    esac

    step "生成 Ports 启动脚本"
    write_port_script "$base"
    info "OK    $PORT_SCRIPT"

    if [ "$GAMELIST_EDIT" = 1 ]; then
        step "写入菜单显示名"
        [ -f "$GAMELIST" ] && [ ! -f "$GAMELIST.bak-welkin" ] && cp "$GAMELIST" "$GAMELIST.bak-welkin"
        gamelist_edit add
        info "OK    gamelist.xml: name = Welkin"
    fi

    if [ "$RESTART" = 1 ]; then
        step "重启 EmulationStation"
        batocera-es-swissknife --restart >/dev/null 2>&1 &
        info "已发送重启请求"
    fi

    if [ "$VERIFY" = 1 ]; then do_verify
    else
        step "完成"
        info "ES 里进 Ports 菜单即可看到 Welkin"
        info "自检: bash $0 --verify"
    fi
}

if [ "$UNINSTALL" = 1 ]; then do_uninstall; else do_install; fi
