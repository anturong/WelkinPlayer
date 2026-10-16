#!/bin/bash
###############################################################################
#  本地端到端构建（WSL / Ubuntu 22.04）：上游源码 → 打补丁 → 编译 → 换进 AppImage
#
#  用法:
#      bash build-patched.sh <上游AppImage> [输出AppImage] [源码ref]
#
#  例:
#      bash build-patched.sh ~/Welkin_1.0.2_amd64.AppImage ~/Welkin-batocera.AppImage
#      bash build-patched.sh ~/Welkin_1.0.2_amd64.AppImage out.AppImage 0c50d2bddd81
#
#  说明:
#    - CI（.github/workflows/batocera-appimage.yml）做的是同一件事，
#      这个脚本是网络不稳或 CI 不可用时的兜底。
#    - 补丁来自 batocera/patches/*.diff，按文件名顺序应用；
#      打不上会立刻报错，说明补丁需要跟着上游更新。
#    - 必须用 tauri CLI 编：裸 cargo build 不会把前端资源嵌进二进制（启动白屏）。
###############################################################################
set -euo pipefail

SRC_APPIMAGE="${1:?用法: build-patched.sh <上游AppImage> [输出AppImage] [源码ref]}"
OUT_APPIMAGE="${2:-$(dirname "$SRC_APPIMAGE")/Welkin_1.0.2_amd64-batocera.AppImage}"
REF="${3:-main}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/atemukesu/WelkinPlayer.git}"
WORK="${WORK:-$HOME/welkin-build}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$(cd "$SCRIPT_DIR/../patches" && pwd)"

[ -f "$SRC_APPIMAGE" ] || { echo "找不到上游 AppImage: $SRC_APPIMAGE" >&2; exit 1; }

# ---------------------------------------------------------------- 1. 依赖
if ! command -v cargo >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential curl wget file unzip git pkg-config patchelf \
        libssl-dev libgtk-3-dev libwebkit2gtk-4.1-dev libjavascriptcoregtk-4.1-dev \
        libsoup-3.0-dev libayatana-appindicator3-dev librsvg2-dev libasound2-dev libxdo-dev \
        squashfs-tools
    # Rust（国内镜像）
    export RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup
    export RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup.sh
    sh /tmp/rustup.sh -y --profile minimal --default-toolchain stable --no-modify-path
fi
export PATH="$HOME/.cargo/bin:/opt/node-v20.19.0-linux-x64/bin:$PATH"

# ---------------------------------------------------------------- 2. cargo 源
# 注意: 清华的 sparse index 里 dl 仍指向 static.crates.io，国内会卡死；
#       必须换成 index 与 dl 同源的镜像（rsproxy）。
mkdir -p "$HOME/.cargo"
if ! grep -q rsproxy "$HOME/.cargo/config.toml" 2>/dev/null; then
    cat >> "$HOME/.cargo/config.toml" <<'EOF'
[source.crates-io]
replace-with = 'rsproxy-sparse'

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
EOF
fi

# ---------------------------------------------------------------- 3. Node / pnpm
if ! command -v node >/dev/null 2>&1; then
    V=v20.19.0
    curl -fsSL "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/$V/node-$V-linux-x64.tar.xz" -o /tmp/node.tar.xz
    mkdir -p /opt && tar -xf /tmp/node.tar.xz -C /opt
    for b in node npm npx corepack; do ln -sf "/opt/node-$V-linux-x64/bin/$b" "/usr/local/bin/$b"; done
fi
npm config set registry https://registry.npmmirror.com >/dev/null 2>&1 || true
command -v pnpm >/dev/null 2>&1 || npm install -g pnpm@9

# ---------------------------------------------------------------- 4. 源码
rm -rf "$WORK/welkin"
mkdir -p "$WORK"
if [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then
    # 具体提交：--branch 不认 SHA，得先 fetch 再 checkout
    git init -q "$WORK/welkin"
    git -C "$WORK/welkin" remote add origin "$UPSTREAM_URL"
    git -C "$WORK/welkin" fetch -q --depth 1 origin "$REF"
    git -C "$WORK/welkin" checkout -q FETCH_HEAD
else
    git clone --quiet --depth 1 -b "$REF" "$UPSTREAM_URL" "$WORK/welkin"
fi
cd "$WORK/welkin"
echo "构建提交: $(git log --oneline -1)"

# ---------------------------------------------------------------- 5. 打补丁
shopt -s nullglob
for p in "$PATCH_DIR"/*.diff; do
    echo "== 应用 $(basename "$p")"
    git apply "$p" || { echo "补丁 $(basename "$p") 打不上：需要跟着上游更新" >&2; exit 1; }
done
[ -f src-tauri/src/playback/spectrum.rs ] || echo "提示: 没看到频谱模块，可能只应用了部分补丁"

# ---------------------------------------------------------------- 6. 构建
pnpm install --frozen-lockfile
pnpm build                                  # 必须先建前端：generate_context! 会读 dist
cargo test --lib --quiet                    # 频谱分析等单测
node_modules/.bin/tauri build --no-bundle   # 关键：必须走 tauri CLI

BIN="$WORK/welkin/src-tauri/target/release/welkinplayer"
echo "--- 资源指纹自检（前端资源 + 补丁痕迹）---"
for pat in index.html desktop-lyric-overlay esc_quit_enabled audio_spectrum_config; do
    printf "  %-24s %s\n" "$pat" "$(grep -a -c "$pat" "$BIN" || true)"
done
sha256sum "$BIN"

# ---------------------------------------------------------------- 7. 换进 AppImage
bash "$SCRIPT_DIR/swap-binary.sh" "$BIN" "$SRC_APPIMAGE" "$OUT_APPIMAGE"
echo
echo "完成: $OUT_APPIMAGE"
echo "装到 Batocera:"
echo "  scp '$OUT_APPIMAGE' root@<batocera>:/userdata/system/"
echo "  # 再把 /userdata/roms/ports/welkin.sh 里的 AppImage 名字改成这个文件"
