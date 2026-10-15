# Welkin on Batocera — 个人复现版

**一句话**：把 **`Welkin_1.0.2_amd64-batocera.AppImage`** 拷到 Batocera 的 `/userdata/system/`，再放一个启动脚本，Ports 菜单就能放出声音。

> `-batocera` 版 = 原版重打包（补齐 GStreamer 插件与解码器）**+ 修掉本地音源代理的上游 bug**，是当前唯一「点播放真的有声音」的版本。
> 上一版 `-fixed` 只解决了打包问题，本地音源仍会被上游 bug 卡住（详见文末「本地音源修复」）。

---

## 1. 为什么需要"修复版"

原版 `Welkin_1.0.2_amd64.AppImage` 有 **打包缺陷**，在**任何** Linux 上都放不出声音：

| 问题 | 证据 | 后果 |
| --- | --- | --- |
| 只带了 GStreamer 1.20.3 核心库，**一个插件都没打包** | 包内 `find -name 'libgst*.so*'` 只有 10 个核心库 | WebKit 造不出 `autoaudiosink` |
| 启动脚本把插件目录指向自己**不存在**的路径 | `GST_PLUGIN_SYSTEM_PATH_1_0=<mount>/usr/lib/gstreamer-1.0` 而该目录不存在 | 一个插件都找不到 |
| 自带 `libdbus-1.so.3` | `dbus-launch: version 'LIBDBUS_PRIVATE_1.14.10' not found` | 系统 dbus-launch 被打崩，密钥环/媒体控制/托盘全废 |
| 无 3D 加速环境（VMware） | `libEGL warning: egl: failed to create dri2 screen` | WebKit 渲染进程 abort → 白屏 |

表现就是：**应用能启动、能扫库，但一按播放（或它启动时自动初始化音频）`WebKitWebProcess` 立刻崩，窗口定格**，看起来像"播放器卡死"；在 VMware 里还可能把整个虚拟机拖死。

---

## 2. 修复版做了什么

重新打包，把修复**全部塞进 AppImage 内部**（不改系统、不需要外部目录）：

```
usr/lib/gstreamer-1.0/        21 个 GStreamer 1.20.x 插件 + gst-plugin-scanner
                              (playback/typefind/audioconvert/audioresample/volume/
                               app/pbtypes/alsa/pulseaudio/autodetect/
                               flac/mpg123/audioparsers/wavparse/id3demux/apetag/audiofx/
                               asf(ASF解复用) / libav(FFmpeg解码) / coreelements)
usr/lib/                      libFLAC.so.8 / liborc-0.4.so.0 / libmpg123.so.0
                              libgstrtp/riff/rtsp/sdp (asfdemux 需要)
                              + 55 个 libavcodec58 运行时(FFmpeg 4.4)
删除 usr/lib/libdbus-1.so.3    改用系统 libdbus，dbus-launch 不再被打崩
apprun-hooks/                 追加 Batocera 适配(见下)
```

写进 AppRun 钩子的环境（因为 AppRun 只 `source` 名为 `linuxdeploy-plugin-gtk.sh` 的那一个钩子，所以是**追加**进去的）：

```bash
export WEBKIT_DISABLE_DMABUF_RENDERER=1     # 无 3D 加速时否则白屏
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export GST_PLUGIN_SCANNER="$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner"
export GST_PLUGIN_FEATURE_RANK="mpg123audiodec:MAX"
# ↑ 关键: 内置 libav 后 decodebin 会抢用 avdec_mp3 导致 MP3 协商失败(not-negotiated)，
#   把实测可用的 mpg123 解码器提到最高优先级即可。
if [ -z "$XDG_RUNTIME_DIR" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then export XDG_RUNTIME_DIR=/var/run; fi
```

**实测结果**（用 WebKit 真正使用的 `playbin` 管线，最小环境 `env -i` 运行）：

| 格式 | 结果 | 解码链 |
| --- | --- | --- |
| MP3 | ✅ 出声 | `mpegaudioparse → mpg123audiodec` |
| FLAC | ✅ 出声 | `flacdec` |
| WMA | ✅ 出声 | `asfdemux → multiqueue → avdec_wmav2 → playsink` |

| 校验项 | 原版 | 修复版 |
| --- | --- | --- |
| `WebKitWebProcess` | 启动即崩 | 稳定存活 |
| 截图内容量 | 11 KB（白屏） | 283 KB（完整界面） |
| 文件数 | 原版 88.7 MB | 修复版 116.7 MB |

---

## 3. 部署（三选一）

### 3.1 最省事：Windows 一键

```powershell
# 需要 Windows 自带 OpenSSH 客户端
powershell -ExecutionPolicy Bypass -File .\install-welkin.ps1 `
    -ComputerName 192.168.17.128 -Password linux -Verify -Restart
```

脚本会自动上传 AppImage、生成 Ports 启动脚本、可选自检、可选重启 ES。
（Batocera 出厂 SSH 账号 `root` / `linux`。IP 以你自己机器为准；VMware NAT 下常见 `192.168.17.128`。）

### 3.2 手动（Batocera 上执行）

```bash
# 上传
scp Welkin_1.0.2_amd64-fixed.AppImage root@<batocera>:/userdata/system/

# 登录后
cd /userdata/system
chmod 755 Welkin_1.0.2_amd64-fixed.AppImage

cat > /userdata/roms/ports/welkin.sh <<'EOF'
#!/bin/bash
export DISPLAY=:0.0
export XDG_RUNTIME_DIR=/var/run
pkill -f welkinplayer 2>/dev/null
sleep 1
cd /userdata/system || exit 1
exec dbus-run-session -- ./Welkin_1.0.2_amd64-fixed.AppImage --no-sandbox
EOF
chmod 755 /userdata/roms/ports/welkin.sh
batocera-es-swissknife --restart     # 重启 ES 后 Ports 菜单出现 Welkin
```

### 3.3 用安装脚本（推荐，带自检/卸载）

```bash
# 把 AppImage 和 install-welkin.sh 一起传到 Batocera
scp Welkin_1.0.2_amd64-fixed.AppImage install-welkin.sh root@<batocera>:/userdata/system/
ssh root@<batocera>
cd /userdata/system
chmod 755 install-welkin.sh
bash install-welkin.sh --verify --restart
```

---

## 4. 自检命令（SSH 直接跑，看报错）

```bash
# 1) 进程：必须同时有 welkinplayer 和 WebKitWebProcess
ps -eo pid,stat,etime,comm | grep -i -e welkin -e WebKit | grep -v grep

# 2) 全量日志（注意 comm 名会被截断成 WebKitWebProces，grep 用 WebKit 就好）
grep -i -e "not found" -e "plugin loader" -e CRITICAL /userdata/system/logs/welkin-app.log | tail

# 3) 抓屏判断是否白屏：白屏约 8~12 KB，正常界面 200 KB+
ffmpeg -y -f x11grab -video_size 1920x1080 -i :0.0 -frames:v 1 /tmp/shot.png && ls -l /tmp/shot.png

# 4) 音频链路（用 AppImage 自带的那套库，模拟 app 真实环境）
PID=$(pgrep -f "welkinplayer --no-sandbox" | head -1)
APPDIR=$(tr '\0' '\n' < /proc/$PID/environ | grep '^APPDIR=' | cut -d= -f2)
for f in /userdata/roms/music/*; do
  env LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/usr/lib/x86_64-linux-gnu" \
      GST_PLUGIN_SYSTEM_PATH_1_0="$APPDIR/usr/lib/gstreamer-1.0" \
      GST_PLUGIN_SCANNER="$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner" \
      GST_PLUGIN_FEATURE_RANK="mpg123audiodec:MAX" XDG_RUNTIME_DIR=/var/run \
      timeout 10 gst-launch-1.0 playbin uri="file://$f" 2>&1 | tail -2
  echo "--- $f"
done
# 期望: "New clock: GstPulseSinkClock"；被打断的 timeout 返回 124 属正常（说明在持续播放）
```

### 已知的无害告警（可忽略）

- `GStreamer element fakevideosink not found` / `WebVTT encoder` —— 来自 gst-plugins-bad，纯提示
- `The name org.freedesktop.secrets was not provided` —— Batocera 没有密钥环服务，只影响匿名统计 ID
- `tauri_plugin_updater: failed to check for updates` —— 机器无外网
- `metadata batch failed for xxx.wma: metadata parse error: Mpeg` —— Welkin 自己的 Rust 元数据解析器把这个 WMA 认成 MPEG，**不影响播放**

---

## 5. 从原始 AppImage 重新构建（换新版本时用）

前提：Batocera 上有 `mksquashfs`（43.x 自带）、Python 3 + `zstandard`（宿主上跑）。

```bash
# 在 Windows/任意机器上：生成 payload（从 Ubuntu 22.04 镜像抓配套插件与 libav 闭包）
python build/fetch-payload.py            # 产出 payload/welkin_gst + payload/welkin_ffmpeg

# 传到 Batocera，然后在设备上重打包
scp -r build payload root@<batocera>:/tmp/
ssh root@<batocera>
cd /tmp && bash build/repack-welkin.sh /userdata/system/Welkin-x.y.z_amd64.AppImage /tmp/payload
# 产出 /userdata/system/<原名>-fixed.AppImage，自包含
```

`repack-welkin.sh` 做的事：解包 → 插件放 `usr/lib/gstreamer-1.0/` → 库放 `usr/lib/` →
删自带 `libdbus-1.so.3` → 把上表环境变量追加进 `apprun-hooks/linuxdeploy-plugin-gtk.sh`
（并在 AppRun 里挂上自己的钩子）→ 用原包的 runtime 字节 + `mksquashfs -comp zstd` 重新拼装。

> **本套件已端到端验证过**：用原始 `Welkin_1.0.2_amd64.AppImage` + 本目录的 payload 重打包，
> 产出 135 MB，最小环境（`env -i`）运行后 MP3 / FLAC / WMA 三种格式 playbin 实测全部出声，
> 界面截图 330 KB 正常渲染。

### 构建陷阱（都是实际踩过的）

1. **版本必须配套**：插件用 **GStreamer 1.20.x**（Ubuntu 22.04/jammy），与 AppImage 自带的 1.20.3 核心库匹配。
   用 Batocera 系统的 1.26 插件会撞 GLib 版本（`undefined symbol: g_once_init_enter_pointer`）；
   反过来用 AppImage 自带的 GLib 2.72 又撑不起 1.26 插件。
2. **`libquadmath.so.0` 必须自带**：Batocera **没有**这个库（有 `libgomp` 但没有 `libquadmath`），
   而 jammy 的 `libavfilter` / `libgfortran` / `liblapack` / `libsphinxbase` 全都依赖它。
   漏掉它的症状很有迷惑性：**MP3/FLAC 正常，只有 WMA 报 “Your GStreamer installation is missing a plug-in”**
   —— 因为 `libgstlibav.so` 是**整体**加载失败（不会只丢一个解码器）。
   `fetch-payload.py` 已把它从排除名单移出，payload 里也带了。
3. **`asfdemux`（ASF 解复用）在 gst-plugins-ugly 里**，libav 只提供解码器；它还需要
   `libgstrtp/riff/rtsp/sdp`，而 AppImage 没打包这几个（会去系统拉 1.26 版然后符号冲突）→ 必须自带。
4. **`WEBKIT_DISABLE_DMABUF_RENDERER=1` 不能漏**：无 3D 加速时 WebKit 的 DMA-BUF 渲染器出不了图（白屏）。
   判断依据不是日志而是**截图文件大小**：白屏约 8~12 KB，正常界面 >200 KB。
5. **别忘了 `GST_PLUGIN_FEATURE_RANK="mpg123audiodec:MAX"`**：装了 libav 之后 `decodebin`
   会优先选 `avdec_mp3`（primary）而 `mpg123audiodec` 只有 marginal(64)，导致 MP3 协商失败
   （`mpegaudioparse: not-negotiated`）。这行是必须的。

### 快速体检

```bash
# 对 payload 里每个 .so 收集缺失依赖（应为空）
for f in payload/welkin_ffmpeg/*.so* payload/welkin_gst/*.so*; do
    m=$(ldd "$f" 2>/dev/null | grep "not found")
    [ -n "$m" ] && echo "$f: $m"
done
```

> 版本对齐很关键：插件必须是 **GStreamer 1.20.x**（Ubuntu 22.04/jammy），
> 与 AppImage 自带的 1.20.3 核心库配套。用 Batocera 系统的 1.26 插件会撞 GLib 版本
> （`undefined symbol: g_once_init_enter_pointer`），用 AppImage 自带的 GLib 又撑不起 1.26 插件。

---

## 6. 目录内容

```
Welkin个人复现版/
├── README.md                              本文件
├── Welkin_1.0.2_amd64-batocera.AppImage   ★ 可用版（116.7 MB, sha256 346952F8…A21F3）
├── install-welkin.sh                      Batocera 侧安装/自检/卸载脚本
├── install-welkin.ps1                     Windows 侧一键（上传+安装）
├── welkin.sh                              Ports 启动脚本（安装脚本会生成同样的内容）
├── patch/
│   └── welkinplayer-1.0.2-patched         打过本地音源补丁的二进制（17.7 MB）
└── build/
    ├── build-patched.sh                   一条命令复现补丁版（WSL/Ubuntu 22.04）
    ├── swap-binary.sh                     把二进制替换进 AppImage 并重新拼装
    ├── fix-local-stream-rewind.diff       上游修复补丁（对应 PR #1）
    ├── repack-welkin.sh                   从原版重打包（需要 payload，见下）
    └── fetch-payload.py                   重新生成 payload（从 jammy 镜像抓包 + ELF 闭包收敛）
```

> **已精简**：为省空间，`payload/`（约 176 MB）与上一版 `-fixed` AppImage（116.7 MB）
> 已从本目录移除，只在 Release 里留了备份 ——
>
> | 需要的东西 | 从哪里取 |
> | --- | --- |
> | `payload/`（重打包用） | Release [r1](https://github.com/anturong/WelkinPlayer/releases/tag/batocera-1.0.2-r1) 的 `welkin-payload.tar.zst`（68 MB，解压即得）；或跑 `python build/fetch-payload.py` |
> | 上一版 `-fixed` AppImage | Release [r1](https://github.com/anturong/WelkinPlayer/releases/tag/batocera-1.0.2-r1)；`build-patched.sh` 的输入就是它 |
> | 原始 `Welkin_1.0.2_amd64.AppImage` | 上游 [atemukesu/WelkinPlayer](https://github.com/atemukesu/WelkinPlayer/releases) 的 1.0.2 |
>
> 设备侧（`/userdata/system`）同样只保留了 `Welkin_1.0.2_amd64-batocera.AppImage`，
> 原版与 `-fixed` 版已删除（释放约 230 MB）。

## 7. 环境备注（本机实测）

| 项目 | 值 |
| --- | --- |
| 目标系统 | Batocera.linux 43.1，kernel 6.18.16，glibc 2.40，Mesa 25.3.6 |
| 系统 GStreamer | 1.26.6（89 个插件） |
| AppImage 自带 | GStreamer 1.20.3 + GLib 2.72 时代 |
| 音乐位置 | `/userdata/roms/music/`（稳定路径）；物理上是 sda3 那块 NTFS，由 Batocera 用 mergerfs 并进来。**注意盘符会漂移，别用 `/media/sdX3/...` 写进 Welkin 的库路径**，见末尾「常见问题」 |
| 虚拟机 | VMware Workstation，NAT 网段 192.168.17.0/24（本机为硬件直通，等同实机） |

---

## 常见问题

### 界面正常、歌名也在，但按播放没声音

**优先怀疑音乐库路径失效，而不是音频栈**（判断依据：ES 菜单/视频预览有声音，只有 Welkin 没声音）。

Welkin 的「本地音乐」源保存的是**绝对路径**。在 VMware 直通或多盘环境下，Batocera 的盘符会漂移：
同一块 1TB USB，某次开机是 `/dev/sda3` → `/media/sda3`，插上直通盘那次变成 `/dev/sdc3` → `/media/sdc3`。
盘符一变，库缓存里歌名还在（界面看着正常），但文件找不到 → **一点播放就静默失败**，听起来就是「没声音」。

修法：把源指到 Batocera 的 **mergerfs 视图 `/userdata/roms/music`**，它对盘符变化免疫：

```bash
# 看当前配置
grep rootPath /userdata/system/.local/share/com.atemukesu.welkinplayer/settings.json

# 改成稳定路径（应用没在运行时操作）
python3 - <<'PY'
import io, json
p = "/userdata/system/.local/share/com.atemukesu.welkinplayer/settings.json"
d = json.load(io.open(p, encoding="utf-8"))
for s in d.get("sources", []):
    s["rootPath"] = "/userdata/roms/music"
io.open(p, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False, indent=2))
PY
```

重启应用后，日志里应出现 `refreshed source …: N files`（N = 实际曲目数）。

### 怎么区分「路径问题」和「音频问题」

用 app 自带的那套库直接播一首（绕过 Welkin 自身逻辑）：

```bash
AP=$(pgrep -f "welkinplayer --no-sandbox" | head -1)
APPDIR=$(tr '\0' '\n' < /proc/$AP/environ | grep '^APPDIR=' | cut -d= -f2)
env -i DISPLAY=:0.0 HOME=/userdata/system PATH=/usr/bin:/bin XDG_RUNTIME_DIR=/var/run \
    LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/usr/lib/x86_64-linux-gnu" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$APPDIR/usr/lib/gstreamer-1.0" \
    GST_PLUGIN_SCANNER="$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner" \
    GST_PLUGIN_FEATURE_RANK=mpg123audiodec:MAX \
    timeout 10 gst-launch-1.0 playbin uri="file:///userdata/roms/music/某首歌.mp3" 2>&1 | tail -3
```

- 出现 `New clock: GstPulseSinkClock`（或 `GstAlsaSinkClock`）→ **音频链路正常**，问题在库路径/曲目状态
- 报 `missing a plug-in` / `not found` → 是打包或插件问题，看第 5 节与构建陷阱

### 播放器卡死 / 整屏白屏

- 白屏：`WEBKIT_DISABLE_DMABUF_RENDERER=1` 没生效（修复版已内嵌；若被别的脚本覆盖请检查 AppRun 钩子）
- 卡死：`WebKitWebProcess` 崩了 —— 先看 `/userdata/system/logs/welkin-app.log` 里的 `not found` / `plugin loader` 关键字
- 快速判断白屏：抓屏文件大小，白屏约 8~12 KB，正常界面 >200 KB

---

## 本地音源修复（上游 bug，需自编译补丁版）

> 解决的现象：**用本地文件夹当音源时，点播放没声音、进度停在 `0:00`**。
> 早期 `-fixed` 版也有这个问题 —— 它不是打包问题，而是**上游代码的 bug**。

### 症状与定位

WebKit 发出的媒体请求**首包不带 `Range`**，直接打向 app 自己的本地代理：

| 请求 | 上游代理的响应 |
| --- | --- |
| `GET /stream?...`（无 Range） | **200 + 0 字节** ← 致命 |
| `GET /stream?...` + `Range: bytes=0-` | 206 + 完整文件（`Content-Range: bytes 0-…/…`） |
| `GET /stream?...` + `Range: bytes=0-99` | 206 + 100 字节 |

于是 GStreamer 报 `typefind: Stream doesn't contain enough data` / `Can't typefind stream`，
播放静默失败。注意 `serve_webdav()` 只是把请求转发给上游 HTTP 服务器，
所以**用 WebDAV 音源不受影响** —— 这是当时判断"问题在代理而不在音频栈"的关键证据。

### 根因

`src-tauri/src/streaming/proxy.rs`：

```rust
let total = file.seek(SeekFrom::End(0))?;   // 取长度，游标停在 EOF
match range.and_then(|v| parse_range(v, total)) {
    Some((start, end)) => { file.seek(SeekFrom::Start(start))?; /* 206 */ }  // ✓ 有 Range 会回绕
    None => { let reader = file.take(total); /* 200 */ }                    // ✗ 无 Range 就从 EOF 读 → 0 字节
}
```

`serve_local()` 与 `serve_cached_file()`（智能缓存命中）两处都有这个问题。
已向上游提交 PR：<https://github.com/atemukesu/WelkinPlayer/pull/1>

### 补丁版

本套件里的 **`Welkin_1.0.2_amd64-batocera.AppImage`**（116.7 MB）：

- 内容 = 上游 main + 上述修复，重新编译 `welkinplayer`，替换进 `-fixed` 版 AppImage
- sha256 `346952F8911FF7DAB792F3F75BCD2900A48D225D65A3CBDD9ABFBBA711FA21F3`
- 实测：MP3 / FLAC / WMA 三首点播放均有声，pipewire 里出现 `welkinplayer` 的流 `[active]`，进度正常推进，日志中 `Can't typefind` 0 次

### 复现构建

```bash
# WSL / Ubuntu 22.04（与 AppImage 的 jammy 基准同源），一条命令走完依赖+编译+替换
bash build/build-patched.sh /path/to/Welkin_1.0.2_amd64-fixed.AppImage
```

脚本里注释了两个实际踩到的坑：

1. **cargo 源**：清华的 sparse index 里 `dl` 仍指向 `static.crates.io`，在国内会**卡死 30 分钟不动**；
   要用 index 与 `dl` 同源的镜像（脚本用 `rsproxy.cn`）。
2. **必须用 tauri CLI 构建**：裸 `cargo build --release` **不会把前端资源嵌进二进制** →
   启动后白屏（`grep -a -c "index-CCoJszDh" 二进制` 为 0 可判定）。脚本用
   `node_modules/.bin/tauri build --no-bundle`，并用资源指纹自检。

若已有编译好的二进制，也可以只做替换：

```bash
scp patch/welkinplayer-1.0.2-patched root@<batocera>:/tmp/
scp build/swap-binary.sh            root@<batocera>:/tmp/
ssh root@<batocera> 'bash /tmp/swap-binary.sh /tmp/welkinplayer-1.0.2-patched \
     /userdata/system/Welkin_1.0.2_amd64-fixed.AppImage \
     /userdata/system/Welkin_1.0.2_amd64-batocera.AppImage'
```
