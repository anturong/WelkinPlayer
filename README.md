> [!IMPORTANT]
> ## ⚡ 开箱可用的 Batocera / Linux 修复版（本 fork 提供）
>
> 上游 `Welkin_1.0.2_amd64.AppImage` 在 Linux 上**放不出声音**，有两个独立原因，本 fork 都已修掉：
>
> 1. **打包缺陷**（原版问题）：包内只有 GStreamer 1.20.3 **核心库、零插件**，还把插件目录指向包内
>    **不存在**的路径 → WebKit 造不出 `autoaudiosink` → 一播放音频 `WebKitWebProcess` 立即崩溃
>    （表现为播放器卡死 / 白屏）。→ 重新打包，补齐 GStreamer 插件与 FFmpeg 解码器，全部内嵌进 AppImage。
> 2. **上游代码 bug**（[PR #1](https://github.com/atemukesu/WelkinPlayer/pull/1)）：本地音源经 app 自带的流代理
>    播放，而该代理在**无 `Range` 请求**时忘了把文件游标回绕到 0（`serve_local()` / `serve_cached_file()`），
>    于是返回 `200` + **0 字节** → GStreamer 报 `Can't typefind stream` → 点播放静默无声
>    （WebDAV 音源走转发路径，不受影响）。
>
> **下载（已实测出声）**
> 👉 [**`Welkin_1.0.2_amd64-batocera.AppImage`**](https://github.com/anturong/WelkinPlayer/releases/tag/batocera-1.0.2-r2)
> 　sha256 `346952f8911ff7dab792f3f75bcd2900a48d225d65a3cbdd9abfbba711fa21f3`
>
> ```bash
> scp Welkin_1.0.2_amd64-batocera.AppImage root@<batocera>:/userdata/system/
> scp welkin.sh root@<batocera>:/userdata/roms/ports/     # 见 batocera 分支，或跑 install-welkin.sh 自动生成
> ```
>
> **实测环境**：Batocera.linux 43.1 / kernel 6.18 / x86_64 / PipeWire。MP3、FLAC、WMA 三首点播放均有声，
> `wpctl status` 里可见 `welkinplayer` 的流 `[active]`，进度正常推进，日志中 `Can't typefind` 计数为 0。
>
> **更多**
> - 完整说明（症状 / 根因代码 / 复现构建 / 踩坑）→ [BATOCERA-FIX.md](BATOCERA-FIX.md) 与 [`batocera` 分支](https://github.com/anturong/WelkinPlayer/tree/batocera)
> - 本地音源修复补丁本身 → [fix-local-stream-rewind.diff](https://github.com/anturong/WelkinPlayer/releases/download/batocera-1.0.2-r2/fix-local-stream-rewind.diff)
> - 重新编译补丁版（WSL/Ubuntu 22.04 一条命令）→ [build-patched.sh](https://github.com/anturong/WelkinPlayer/releases/download/batocera-1.0.2-r2/build-patched.sh)
>
> > 注：AppImage 为 116.7 MB，超过 GitHub **单文件 100 MB** 限制，无法放进 git 仓库，因此只作为
> > [Release 资产](https://github.com/anturong/WelkinPlayer/releases/tag/batocera-1.0.2-r2) 提供。
>
> ---

![Welkin banner](docs/assets/banner.svg)

**[中文](README.md) · [English](README.en.md)**

# Welkin

基于 [Tauri 2](https://v2.tauri.app/) 的跨平台音乐播放器。通过 WebDAV 或本地文件夹读取音乐收藏，把资料、歌单与播放进度跨设备同步，并提供 AMLL 逐字歌词、桌面悬浮歌词与系统媒体控制。

- 仓库：<https://github.com/atemukesu/WelkinPlayer>
- 支持平台：Windows / macOS / Linux / Android
- 界面语言：简体中文、English

## 截图

![](/docs/assets/screenshot1.png)
![](/docs/assets/screenshot2.png)
![](/docs/assets/screenshot3.png)
![](/docs/assets/screenshot4.png)

## 功能特性

- **音乐来源**：同时配置多个 WebDAV 与本地文件夹来源，可指定其中一个作为云端同步位置。
- **歌词**：AMLL 逐字歌词渲染；在线歌词按顺序从 QQ 音乐、网易云音乐、AMLL 歌词库获取；本地同名字幕优先。
- **桌面悬浮歌词**：独立的透明歌词窗口（Android 为系统悬浮窗）。
- **系统媒体控制**：Windows SMTC、macOS Now Playing、Linux MPRIS、Android MediaSession。
- **流式播放与缓存**：Rust 本地回环代理对流媒体做 Range 透传，按网络状态智能缓存，支持手动置顶。
- **跨设备同步**：昵称、歌单、收藏、播放进度等同步到指定来源。
- **音乐管理**：元数据/封面读取与编辑、播放统计与排名。
- **主题**：浅色/深色与多种主题色。

## 技术栈

| 层 | 技术 |
| --- | --- |
| 壳与后端 | Tauri 2（Rust） |
| 前端 | Vue 3 + TypeScript + Vite |
| 状态/i18n | Pinia、vue-i18n |
| 样式 | Tailwind CSS 4 |
| 歌词渲染 | [@applemusic-like-lyrics](https://github.com/amll-dev/applemusic-like-lyrics) |
| 更新 | tauri-plugin-updater（桌面） |

## 环境要求

- Node.js 20+ 与 [pnpm](https://pnpm.io/) 9
- Rust stable（rustup）
- 平台依赖：
  - Windows：WebView2（Win11 自带）
  - macOS：Xcode Command Line Tools
  - Linux：`libwebkit2gtk-4.1-dev`、`libappindicator3-dev`、`librsvg2-dev`、`patchelf`、`libdbus-1-dev`
- 构建 Android 额外需要：JDK 17、Android SDK、Android NDK（r26b）、Android 目标 Rust 组件

## 开发

```bash
pnpm install        # 安装依赖

pnpm tauri dev      # 启动完整桌面应用（Rust + 前端热更新）
pnpm dev            # 仅启动前端（Vite，端口 1420）
```

## 构建

```bash
pnpm build                     # 仅构建前端（含 vue-tsc 类型检查）
pnpm tauri build               # 构建桌面安装包

pnpm tauri android build --apk # 构建 Android APK
```

> Android release 签名通过环境变量注入：`ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`；未配置时回退为 debug 签名。

## 目录结构

```
.
├─ src/                 # Vue 前端
│  ├─ views/            # 页面（设置、来源、歌词编辑等）
│  ├─ stores/           # Pinia 状态
│  └─ lib/              # 通用工具与前端契约
├─ src-tauri/           # Rust 后端
│  ├─ src/commands/     # Tauri 命令（媒体、WebDAV、更新等）
│  ├─ gen/android/      # Android 工程
│  └─ tauri.conf.json   # 应用配置（版本、更新器等）
├─ scripts/             # 构建辅助脚本
└─ .github/workflows/   # CI（发布流程）
```

## 许可证

本项目基于 [GNU General Public License v3.0 only](https://www.gnu.org/licenses/gpl-3.0.html)（`GPL-3.0-only`）发布，详见 [LICENSE](LICENSE)。
