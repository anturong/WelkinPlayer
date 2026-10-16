# Batocera 可用版 {{VERSION}}

- AppImage 外壳取自上游 release：`{{TAG}}`
- 二进制由上游源码 ref `{{REF}}` + 本仓库补丁编出
- AppImage sha256：`{{SHA256}}`

## 这个构建做了什么

1. **Escape 退出**（kiosk 需要）：启动器设 `WELKIN_ESC_QUITS=1` 后，按 Esc 退回 EmulationStation；
   全屏可视化里 Esc 只退全屏，回到界面后再按才退程序。
2. **全屏音频可视化**：侧栏「可视化」（位于「全部曲目」与「歌手」之间）→ 选效果
   （镜像频谱 / 经典柱状 / 环形扩散）→「开始全屏」；移动鼠标唤出退出控件。
   分析在 Rust 播放引擎里做（2048 点 FFT，读的是送进环形缓冲之后的同一批样本），
   **不碰音频线程**，且没人看时完全不工作。
3. **Batocera 适配**：
   - 去掉 AppImage 自带的 `libdbus-1.so.3` —— 它会打崩系统的 `dbus-launch`
   - 无 3D 加速时让 WebKit 走软件路径（`WEBKIT_DISABLE_DMABUF_RENDERER`），避免白屏；
     真机有可用 GPU 时，在启动器里设 `WELKIN_GL_ACCEL=1` 即可恢复硬件合成
   - `XDG_RUNTIME_DIR` 兜底为 `/var/run`（PipeWire/PulseAudio 需要）
4. **不再打包 GStreamer/libav 闭包**：新版播放由 rodio + symphonia 在 Rust 里解码，不经过
   webview 的 GStreamer —— 所以这版只有 86 MB（r1/r2 是 117~119 MB）。

## 安装

```sh
scp Welkin_{{VERSION}}_amd64-batocera.AppImage root@<batocera>:/userdata/system/
# 然后把 /userdata/roms/ports/welkin.sh 里的 AppImage 名字改成它，并确保有：
#   export WELKIN_ESC_QUITS=1
```

## 自检

```sh
sha256sum Welkin_{{VERSION}}_amd64-batocera.AppImage   # 应等于上面的值
```

## 附件

- `Welkin_{{VERSION}}_amd64-batocera.AppImage` —— 可直接用
- `welkinplayer-{{VERSION}}-patched` —— 打过补丁的二进制（想换进别的 AppImage 时用）
- `repack-welkin.sh` / `swap-binary.sh` / `build-patched.sh` —— 复现脚本
- `0002-escape-quit.diff` / `0003-audio-visualizer.diff` —— 两个补丁

上游 PR：<https://github.com/atemukesu/WelkinPlayer/pull/3>
