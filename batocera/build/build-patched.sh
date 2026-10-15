#!/bin/bash
###############################################################################
#  缂栬瘧銆屼慨濂芥湰鍦伴煶婧愩€嶇殑 welkinplayer锛屽苟鏇挎崲杩?AppImage
#
#  鑳屾櫙锛氫笂娓?WelkinPlayer 鐨勬湰鍦版祦浠ｇ悊鍦ㄣ€屾棤 Range 璇锋眰銆嶆椂涓嶅洖缁曟枃浠舵父鏍囷紝
#        瀵艰嚧鏈湴鏂囦欢澶归煶婧愯繑鍥?200 + 0 瀛楄妭 鈫?WebKit 鎶?"Can't typefind stream"
#        鈫?鎾斁鏃犲０銆備笂娓?PR: https://github.com/atemukesu/WelkinPlayer/pull/1
#
#  鏈剼鏈湪 WSL/Ubuntu 22.04 閲岃窇锛堜笌 AppImage 鐨?jammy 鍩哄噯鍚屾簮锛夈€?#  鐢ㄦ硶: bash build-patched.sh <鍘熷AppImage> [杈撳嚭AppImage]
###############################################################################
set -euo pipefail

SRC_APPIMAGE="${1:?鐢ㄦ硶: build-patched.sh <鍘熷AppImage> [杈撳嚭AppImage]}"
OUT_APPIMAGE="${2:-$(dirname "$SRC_APPIMAGE")/Welkin_1.0.2_amd64-batocera.AppImage}"
WORK="${WORK:-$HOME/welkin-build}"
FIX_BRANCH_URL="https://github.com/anturong/WelkinPlayer.git"
FIX_BRANCH="fix/local-stream-rewind"

# ---------------------------------------------------------------- 1. 渚濊禆
if ! command -v cargo >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential curl wget file unzip git pkg-config patchelf \
        libssl-dev libgtk-3-dev libwebkit2gtk-4.1-dev libjavascriptcoregtk-4.1-dev \
        libsoup-3.0-dev libayatana-appindicator3-dev librsvg2-dev libasound2-dev libxdo-dev
    # Rust锛堝浗鍐呴暅鍍忥級
    export RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup
    export RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup.sh
    sh /tmp/rustup.sh -y --profile minimal --default-toolchain stable --no-modify-path
fi
export PATH="$HOME/.cargo/bin:/opt/node-v20.19.0-linux-x64/bin:$PATH"

# ---------------------------------------------------------------- 2. cargo 婧?# 娉ㄦ剰锛氭竻鍗庣殑 sparse index 閲?dl 浠嶆寚鍚?static.crates.io锛屽湪鍥藉唴浼氬崱姝伙紱
#       蹇呴』鎹㈡垚 index 涓?dl 鍚屾簮鐨勯暅鍍忥紙rsproxy锛夈€?mkdir -p "$HOME/.cargo"
cat > "$HOME/.cargo/config.toml" <<'EOF'
[source.crates-io]
replace-with = 'rsproxy-sparse'

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
EOF

# ---------------------------------------------------------------- 3. Node/pnpm
if ! command -v node >/dev/null 2>&1; then
    V=v20.19.0
    curl -fsSL "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/$V/node-$V-linux-x64.tar.xz" -o /tmp/node.tar.xz
    mkdir -p /opt && tar -xf /tmp/node.tar.xz -C /opt
    for b in node npm npx corepack; do ln -sf "/opt/node-$V-linux-x64/bin/$b" "/usr/local/bin/$b"; done
fi
npm config set registry https://registry.npmmirror.com >/dev/null 2>&1 || true
command -v pnpm >/dev/null 2>&1 || npm install -g pnpm@9

# ---------------------------------------------------------------- 4. 婧愮爜
rm -rf "$WORK/welkin"
mkdir -p "$WORK"
git clone --quiet --depth 1 -b "$FIX_BRANCH" "$FIX_BRANCH_URL" "$WORK/welkin"
cd "$WORK/welkin"
echo "鏋勫缓鎻愪氦: $(git log --oneline -1)"
grep -q 'Same as serve_local' src-tauri/src/streaming/proxy.rs || { echo "琛ヤ竵涓嶅湪婧愮爜閲岋紒" >&2; exit 1; }

# ---------------------------------------------------------------- 5. 鏋勫缓
pnpm install --frozen-lockfile
# 鍏抽敭锛氬繀椤荤敤 tauri CLI锛堣８ cargo build 涓嶄細宓屽叆鍓嶇璧勬簮 鈫?鍚姩鐧藉睆锛?node_modules/.bin/tauri build --no-bundle

BIN="$WORK/welkin/src-tauri/target/release/welkinplayer"
echo "--- 璧勬簮鎸囩汗鑷锛堝簲涓?1 / 8 / 3锛?---"
for pat in index-CCoJszDh index.html desktop-lyric-overlay; do
    printf "  %-22s %s\n" "$pat" "$(grep -a -c "$pat" "$BIN" || true)"
done
sha256sum "$BIN"

# ---------------------------------------------------------------- 6. 鏇挎崲杩?AppImage
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/swap-binary.sh" "$BIN" "$SRC_APPIMAGE" "$OUT_APPIMAGE"
echo
echo "瀹屾垚锛?OUT_APPIMAGE"
echo "瑁呭埌 Batocera锛?
echo "  scp '$OUT_APPIMAGE' root@<batocera>:/userdata/system/"
echo "  # 鍐嶆妸 /userdata/roms/ports/welkin.sh 閲岀殑 AppImage 鍚嶅瓧鏀规垚瀹?
