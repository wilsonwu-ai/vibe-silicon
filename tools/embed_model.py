#!/usr/bin/env python3
"""Turn a llama2.c checkpoint into C arrays.

The DE10-Lite has no SD card and no filesystem, so there is nothing for run.c's
fopen()/mmap() to open. The weights have to arrive as part of the executable.

    python3 tools/embed_model.py            # writes embed/model260k.h, embed/tok512.h
"""
import os, struct, sys, urllib.request

BASE = "https://huggingface.co/karpathy/tinyllamas/resolve/main"
FILES = {"stories260K.bin": f"{BASE}/stories260K/stories260K.bin",
         "tok512.bin":      f"{BASE}/stories260K/tok512.bin"}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS, EMBED = os.path.join(ROOT, "models"), os.path.join(ROOT, "embed")
# The headers are also the build inputs for Justin's folder, which has to work
# as a standalone zip. Written to both places so they cannot drift apart.
DIST = os.path.join(ROOT, "dist", "llama-nios")


def fetch(name, url):
    os.makedirs(MODELS, exist_ok=True)
    dst = os.path.join(MODELS, name)
    if not os.path.exists(dst):
        print(f"  downloading {name} ...")
        urllib.request.urlretrieve(url, dst)
    return dst


def emit(path, blob, sym, src):
    with open(path, "w") as f:
        f.write(f"/* auto-generated from {src} -- {len(blob)} bytes. Do not edit. */\n")
        f.write("#include <stdint.h>\n")
        f.write(f"const unsigned int {sym}_len = {len(blob)}u;\n")
        # aligned(8) so the float* cast inside run.c is legal on a 32-bit core
        f.write(f"__attribute__((aligned(8))) const unsigned char {sym}[] = {{\n")
        for i in range(0, len(blob), 16):
            f.write("  " + ",".join(f"0x{b:02x}" for b in blob[i:i + 16]) + ",\n")
        f.write("};\n")


def main():
    os.makedirs(EMBED, exist_ok=True)
    os.makedirs(DIST, exist_ok=True)
    model = open(fetch("stories260K.bin", FILES["stories260K.bin"]), "rb").read()
    tok = open(fetch("tok512.bin", FILES["tok512.bin"]), "rb").read()

    keys = ["dim", "hidden_dim", "n_layers", "n_heads", "n_kv_heads", "vocab_size", "seq_len"]
    cfg = dict(zip(keys, struct.unpack("<7i", model[:28])))
    print("  config:", cfg)

    for d in (EMBED, DIST):
        emit(os.path.join(d, "model260k.h"), model, "model260k", "stories260K.bin")
        emit(os.path.join(d, "tok512.h"), tok, "tok512", "tok512.bin")

    dim, hd, L, nh, nkv, V, SL = (cfg[k] for k in keys)
    kvd = (dim // nh) * nkv
    state = (dim * 6 + hd * 2 + nh * SL + abs(V)) * 4 + L * SL * kvd * 4 * 2
    total = len(model) + len(tok) + state
    print(f"  weights {len(model)/1024:8.1f} KB")
    print(f"  tokenizer {len(tok)/1024:6.1f} KB")
    print(f"  runtime  {state/1024:8.1f} KB")
    print(f"  TOTAL    {total/1024:8.1f} KB of 65536 KB SDRAM = {total/1024/65536*100:.2f}%")


if __name__ == "__main__":
    main()
