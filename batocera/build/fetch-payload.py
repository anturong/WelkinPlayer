#!/usr/bin/env python3
"""生成 repack 所需的 payload/：

  payload/welkin_gst/     与 AppImage 自带 GStreamer 1.20.3 核心库配套的插件 + 支撑库
  payload/welkin_ffmpeg/  libavcodec58 等 FFmpeg 4.4 运行时闭包（WMA/M4A/APE 等解码）

数据来源：Ubuntu 22.04 (jammy) 的 .deb 包（插件必须与 1.20.x 核心配套！）

用法：
    pip install zstandard
    python fetch-payload.py            # 默认输出到脚本同级的 ../payload
    python fetch-payload.py --out D:\\some\\payload --mirror https://mirrors.tuna.tsinghua.edu.cn/ubuntu
"""
import argparse
import gzip
import io
import os
import re
import shutil
import struct
import sys
import tarfile
import urllib.request

DEFAULT_MIRROR = "https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
SUITES = [("jammy", "main"), ("jammy", "universe"),
          ("jammy-updates", "main"), ("jammy-updates", "universe")]

# 包名 -> 需要从中取出的文件名模式
GST_TAKE = {
    "libgstreamer1.0-0":              [r"^libgstcoreelements\.so$", r"^gst-plugin-scanner$"],
    "gstreamer1.0-plugins-base":      [r"^libgst(playback|typefindfunctions|audioconvert|audioresample|audiorate|volume|app|pbtypes)\.so$"],
    "gstreamer1.0-plugins-good":      [r"^libgst(autodetect|flac|audioparsers|wavparse|id3demux|apetag|audiofx|pulseaudio|mpg123)\.so$"],
    "gstreamer1.0-plugins-ugly":      [r"^libgstasf\.so$"],
    "gstreamer1.0-alsa":              [r"^libgstalsa\.so$"],
    "libgstreamer-plugins-base1.0-0": [r"^libgst(rtp|riff|rtsp|sdp)-1\.0\.so\.0(\.[0-9]+)*$"],
    "libflac8":                       [r"^libFLAC\.so\.8(\.[0-9.]*)?$"],
    "libmpg123-0":                    [r"^libmpg123\.so\.0(\.[0-9.]*)?$"],
    "liborc-0.4-0":                   [r"^liborc-0\.4\.so\.0(\.[0-9.]*)?$"],
    "gstreamer1.0-libav":             [r"^libgstlibav\.so$"],
}
# libav 闭包的种子包（其 Depends 会拉进 libavcodec58 等）
FFMPEG_SEEDS = ["gstreamer1.0-libav", "libavcodec58", "libavformat58", "libavutil56",
                "libavfilter7", "libswresample3", "libswscale5", "libavdevice58"]
# 绝不能混装的基础运行库（设备 glibc 更新，且这些必须用系统版）
BLOCK = {"libc6", "libc6-dev", "libgcc-s1", "libgcc1", "libstdc++6", "zlib1g",
         "libcrypt1", "libatomic1", "gcc-12-base",
         "libmount1", "libblkid1", "libuuid1", "libsmartcols1", "libfdisk1",
         "libselinux1", "libpcre2-8-0", "libattr1", "libacl1", "libcap2",
         "liblzma5", "libbz2-1.0", "liblz4-1", "libzstd1", "libudev1",
         "libsystemd0", "libffi8", "libtasn1-6", "libp11-kit0", "base-files"}
# ELF 闭包里不再重复打包的（由 glibc / AppImage 自带 / payload 已提供）
SKIP_SONAME = {
    "libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "librt.so.1",
    "libgcc_s.so.1", "libstdc++.so.6", "ld-linux-x86-64.so.2", "libresolv.so.2",
    "libutil.so.1", "libanl.so.1", "libnsl.so.1", "libz.so.1", "libz.so",
    "libgstreamer-1.0.so.0", "libgstbase-1.0.so.0", "libgstaudio-1.0.so.0",
    "libgstvideo-1.0.so.0", "libgstpbutils-1.0.so.0", "libgsttag-1.0.so.0",
    "libgstapp-1.0.so.0", "libgstallocators-1.0.so.0", "libgstfft-1.0.so.0",
    "libgstgl-1.0.so.0", "libglib-2.0.so.0", "libgobject-2.0.so.0",
    "libgio-2.0.so.0", "libgmodule-2.0.so.0", "libgthread-2.0.so.0",
    "liborc-0.4.so.0", "libFLAC.so.8", "libmpg123.so.0",
}
PT_LOAD, PT_DYNAMIC, DT_NEEDED, DT_STRTAB = 1, 2, 1, 5

try:
    import zstandard
except ImportError:
    print("需要 zstandard: pip install zstandard", file=sys.stderr)
    sys.exit(3)


def fetch(url, timeout=300):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def build_index(mirror):
    idx = {}
    for suite, comp in SUITES:
        url = f"{mirror}/dists/{suite}/{comp}/binary-amd64/Packages.gz"
        try:
            blob = gzip.decompress(fetch(url, 180))
        except Exception as exc:                       # noqa: BLE001
            print(f"  跳过索引 {suite}/{comp}: {exc}")
            continue
        stanza = {}
        for line in blob.decode("utf-8", "replace").splitlines():
            if not line.strip():
                if "Package" in stanza:
                    name = stanza["Package"]
                    old = idx.get(name)
                    if old is None or stanza.get("Version", "") > old.get("Version", ""):
                        idx[name] = stanza
                stanza = {}
                continue
            if line[0] in " \t" or ":" not in line:
                continue
            k, v = line.split(":", 1)
            stanza[k.strip()] = v.strip()
        print(f"  索引 {suite}/{comp}: {len(idx)} 个包累计")
    return idx


def dep_names(depends):
    for part in depends.split(","):
        part = re.sub(r"\(.*?\)", "", part.split("|")[0]).strip().split(":")[0].strip()
        if part:
            yield part


def iter_ar(path):
    with open(path, "rb") as fh:
        if fh.read(8) != b"!<arch>\n":
            raise ValueError("不是 ar 归档")
        while True:
            head = fh.read(60)
            if len(head) < 60:
                return
            name = head[0:16].decode("ascii", "replace").strip().rstrip("/")
            try:
                size = int(head[48:58].decode("ascii").strip())
            except ValueError:
                return
            data = fh.read(size)
            if size % 2:
                fh.read(1)
            yield name, data


def extract_deb(path, dest):
    payload = None
    for name, blob in iter_ar(path):
        if name.startswith("data.tar"):
            payload = (name, blob)
            break
    if not payload:
        raise ValueError("没有 data.tar")
    name, blob = payload
    if name.endswith(".zst"):
        raw = zstandard.ZstdDecompressor().stream_reader(io.BytesIO(blob)).read()
    elif name.endswith(".xz"):
        import lzma
        raw = lzma.decompress(blob)
    elif name.endswith(".gz"):
        raw = gzip.decompress(blob)
    else:
        raw = blob
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as tf:
        tf.extractall(dest, members=tf.getmembers())


def elf_needed(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        return []
    e_phoff, = struct.unpack_from("<Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)
    loads, dyn = [], None
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, = struct.unpack_from("<I", data, off)
        p_offset, p_vaddr, _p_paddr, p_filesz = struct.unpack_from("<QQQQ", data, off + 8)
        if p_type == PT_LOAD:
            loads.append((p_vaddr, p_offset, p_filesz))
        elif p_type == PT_DYNAMIC:
            dyn = (p_offset, p_filesz)
    if not dyn:
        return []
    d_off, d_size = dyn
    strtab, entries = None, []
    for i in range(d_size // 16):
        tag, val = struct.unpack_from("<QQ", data, d_off + i * 16)
        if tag == DT_STRTAB:
            strtab = val
        elif tag == DT_NEEDED:
            entries.append(val)
    if strtab is None:
        return []
    base = None
    for v, o, sz in loads:
        if v <= strtab < v + sz:
            base = o + (strtab - v)
            break
    if base is None:
        return []
    out = []
    for noff in entries:
        end = data.index(b"\x00", base + noff)
        out.append(data[base + noff:end].decode("ascii", "replace"))
    return out


def download_pkg(idx, name, cache):
    stanza = idx.get(name)
    if not stanza:
        print(f"  !! 找不到包: {name}")
        return None
    rel = stanza["Filename"]
    deb = os.path.join(cache, os.path.basename(rel))
    if not os.path.exists(deb):
        data = fetch(f"{MIRROR}/{rel}")
        with open(deb, "wb") as fh:
            fh.write(data)
    return deb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "payload"))
    ap.add_argument("--mirror", default=DEFAULT_MIRROR)
    ap.add_argument("--cache", default=None)
    args = ap.parse_args()

    global MIRROR
    MIRROR = args.mirror.rstrip("/")
    out = os.path.abspath(args.out)
    gst_dir = os.path.join(out, "welkin_gst")
    ff_dir = os.path.join(out, "welkin_ffmpeg")
    cache = args.cache or os.path.join(out, ".cache")
    work = os.path.join(out, ".work")
    for d in (gst_dir, ff_dir, cache, work):
        os.makedirs(d, exist_ok=True)

    print("== 读取 Ubuntu jammy 包索引 ==")
    idx = build_index(MIRROR)

    print("\n== 抓取 GStreamer 1.20.x 插件与支撑库 ==")
    got = 0
    for pkg, patterns in GST_TAKE.items():
        deb = download_pkg(idx, pkg, cache)
        if not deb:
            continue
        dest = os.path.join(work, pkg)
        if not os.path.isdir(dest):
            extract_deb(deb, dest)
        take = set()
        for root, _dirs, files in os.walk(dest):
            for fn in files:
                if any(re.match(p, fn) for p in patterns):
                    take.add(os.path.join(root, fn))
        for src in sorted(take):
            shutil.copy2(src, os.path.join(gst_dir, os.path.basename(src)))
            got += 1
        print(f"  {pkg:<34} {len(take)} 个文件")
    print(f"  -> {gst_dir} 共 {got} 个文件, "
          f"{sum(os.path.getsize(os.path.join(gst_dir, f)) for f in os.listdir(gst_dir))/1e6:.1f} MB")

    print("\n== 解析 libav 依赖闭包 ==")
    seen, queue, resolved = set(), list(FFMPEG_SEEDS), {}
    while queue:
        name = queue.pop(0)
        if name in seen or name in BLOCK:
            continue
        seen.add(name)
        stanza = idx.get(name)
        if not stanza:
            continue
        resolved[name] = stanza
        for dep in dep_names(stanza.get("Depends", "")):
            if dep not in seen and dep not in BLOCK:
                queue.append(dep)
    print(f"  {len(resolved)} 个包")

    print("\n== 下载并解包 ==")
    for name in sorted(resolved):
        deb = download_pkg(idx, name, cache)
        if not deb:
            continue
        dest = os.path.join(work, name)
        if not os.path.isdir(dest):
            try:
                extract_deb(deb, dest)
            except Exception as exc:                   # noqa: BLE001
                print(f"  解包失败 {name}: {exc!r}")

    print("\n== 收集 .so 并按 ELF NEEDED 收敛 ==")
    pool = {}
    for root, _dirs, files in os.walk(work):
        for fn in files:
            if ".so" in fn and not os.path.islink(os.path.join(root, fn)):
                pool.setdefault(fn, os.path.join(root, fn))
    print(f"  候选 {len(pool)} 个")
    got, queue = {}, list(["libgstlibav.so"])
    missing = set()
    while queue:
        name = queue.pop(0)
        if name in SKIP_SONAME or name in got:
            continue
        path = pool.get(name)
        if not path:
            missing.add(name)
            continue
        got[name] = path
        for dep in elf_needed(path):
            if dep not in SKIP_SONAME and dep not in got:
                queue.append(dep)
    total = 0
    for name, path in sorted(got.items()):
        shutil.copy2(path, os.path.join(ff_dir, name))
        total += os.path.getsize(path)
    print(f"  -> {ff_dir} 共 {len(got)} 个 .so, {total/1e6:.1f} MB")
    if missing:
        print(f"  未纳入({len(missing)}): " + ", ".join(sorted(missing)[:20]))

    print("\n== 清理中间产物 ==")
    shutil.rmtree(work, ignore_errors=True)
    print(f"  保留 deb 缓存: {cache}")
    print("\n完成。把 payload 目录连同 build/ 一起拷到 Batocera，运行:")
    print("  bash build/repack-welkin.sh <原始AppImage> <payload目录>")


if __name__ == "__main__":
    main()
