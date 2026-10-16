# Batocera 可用版 {{VERSION}}

- AppImage 取自上游 release：`{{TAG}}`
- 二进制与补丁基于上游源码 ref：`{{REF}}`（v1.0.2 的 tag 是旧模块结构，补丁针对 main）

上游 `{{TAG}}` 的 AppImage 在 Linux / Batocera 上**放不出声音**，原因有两个独立问题，本构建都已修掉：

## 1. 打包缺陷（上游 AppImage 本身）

包内只有 GStreamer 1.20.3 **核心库、零插件**，还把 `GST_PLUGIN_SYSTEM_PATH_1_0` 指向包内**不存在**的目录
→ WebKit 造不出 `autoaudiosink`，一播放音频 `WebKitWebProcess` 立刻崩溃（表现为播放器卡死 / 白屏）。

**本构建**：把 GStreamer 插件与 FFmpeg(libav) 解码器闭包塞进 AppImage，并追加 Batocera 适配环境变量
（`WEBKIT_DISABLE_DMABUF_RENDERER=1` 等），同时删掉包内自带的 `libdbus-1.so.3`。

## 2. 上游代码 bug：本地音源无声（补丁 0001）

流代理在**无 `Range` 请求**时忘了把文件游标回绕到 0（`serve_local()` / `serve_cached_file()`），
于是返回 `200` + **0 字节** → GStreamer 报 `Can't typefind stream` → 点播放静默无声。
（WebDAV 音源走转发路径，不受影响。）

修复：两处 200 分支先 `seek(SeekFrom::Start(0))`；并把 `total as usize` 换成 `usize::try_from(total).ok()`，
32 位目标上超过 4 GiB 的文件改走 chunked 传输而不是被截断。
已提上游：<https://github.com/atemukesu/WelkinPlayer/pull/1>

## 3. Batocera 适配：Escape 退出（补丁 0002）

上游把主窗口的关闭请求拦截为「隐藏到托盘」，所以按 Escape 退不出去。本构建新增
`quit_application` / `esc_quit_enabled` 两个命令，前端在全局 `keydown` 里处理 Escape；
开关走环境变量 `WELKIN_ESC_QUITS=1`（由 Batocera 启动脚本设置），**桌面版行为完全不变**。

## 资产

| 文件 | 说明 | sha256 |
| --- | --- | --- |
| `Welkin_{{VERSION}}_amd64-batocera.AppImage` | **直接用这个**：自包含，插件/补丁全部内置 | `{{SHA256}}` |
| `welkinplayer-{{VERSION}}-patched` | 打过补丁的 `welkinplayer` 二进制 | 见 Release 内 `sha256` 输出 |
| `0001-streaming-rewind.diff` / `0002-escape-quit.diff` | 两个补丁本身 | — |
| `build-patched.sh` / `swap-binary.sh` | 本地复现构建 / 二进制替换 | — |

## 安装

```bash
scp Welkin_{{VERSION}}_amd64-batocera.AppImage root@<batocera>:/userdata/system/
scp welkin.sh root@<batocera>:/userdata/roms/ports/     # 见 batocera 分支
ssh root@<batocera> 'chmod +x /userdata/system/Welkin_{{VERSION}}_amd64-batocera.AppImage \
                     /userdata/roms/ports/welkin.sh'
```

音频源建议指向 **`/userdata/roms/music`**（mergerfs 视图）——盘符在直通/多盘环境下会漂移，
写 `/media/sdX3/...` 会失效导致「库里有歌名但播放无声」，详见 `README.md` 的常见问题。

## 验证

三种格式（MP3 / FLAC / WMA）实测：点播放有声音，`wpctl status` 里出现 `welkinplayer` 的流 `[active]`，
进度正常推进，日志中 `Can't typefind` 为 0；Escape 可退出回 EmulationStation。

---

本构建由 GitHub Actions 自动产出（`.github/workflows/batocera-appimage.yml`），
上游发新版后无需人工介入。许可：WelkinPlayer 为 GPL-3.0，本包为其衍生重打包，同样遵循 GPL-3.0。
