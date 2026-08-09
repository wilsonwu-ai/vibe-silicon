#!/usr/bin/env python3
"""Turn a llama2.c checkpoint into C arrays.

The DE10-Lite has no SD card and no filesystem, so there is nothing for run.c's
fopen()/mmap() to open. The weights have to arrive as part of the executable.

    python3 tools/embed_model.py            # writes embed/model260k.h, embed/tok512.h
    python3 tools/embed_model.py --q8       # also writes embed/model260k_q8.h

--q8 additionally quantizes the fp32 checkpoint to int8 weights with one fp32
scale per output row (see MAGIC/quantize() below for the format and why this
project cannot reuse upstream llama2.c's runq.c group-quantization scheme).
The fp32 header is still written every run -- this is additive, not a
replacement; both `run_baremetal.c` and `run_baremetal_q8.c` stay buildable.
"""
import array
import os
import struct
import sys
import urllib.request

BASE = "https://huggingface.co/karpathy/tinyllamas/resolve/main"
FILES = {"stories260K.bin": f"{BASE}/stories260K/stories260K.bin",
         "tok512.bin":      f"{BASE}/stories260K/tok512.bin"}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS, EMBED = os.path.join(ROOT, "models"), os.path.join(ROOT, "embed")
# The headers are also the build inputs for Justin's folder, which has to work
# as a standalone zip. Written to both places so they cannot drift apart.
DIST = os.path.join(ROOT, "dist", "llama-nios")

# Sentinel int32 at the front of the quantized blob's tensor section (right
# after the untouched 7-int Config header) so a stale or mismatched q8 header
# fails loudly in read_checkpoint() instead of silently misreading weights.
Q8_MAGIC = 0x51385653


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


def quantize_tensor(values, rows, cols, name, stats):
    """Symmetric per-output-row int8 quantization, no zero-point.

    `values` is a flat row-major (rows, cols) view -- exactly the layout
    matmul(xout, x, w, n=cols, d=rows) expects (w[i*n+j]). One fp32 scale per
    row, unconstrained by `cols`, unlike upstream runq.c's fixed group size
    (which would need GS <= gcd(64, 172) = 4 here -- worse than fp32; see the
    plan). `cols` must be a multiple of 4 so the C matmul can unpack 4
    int8 weights per 32-bit SDRAM word with no tail case; asserted below.

    Returns (q_bytes, scale_bytes).
    """
    assert cols % 4 == 0, f"{name}: cols={cols} not a multiple of 4"
    assert len(values) == rows * cols, f"{name}: {len(values)} != {rows}*{cols}"
    q = bytearray(rows * cols)
    scales = array.array('f', [0.0]) * rows
    max_abs_err = 0.0
    sq_err = sq_val = 0.0
    for r in range(rows):
        base = r * cols
        row = values[base:base + cols]
        wmax = max(abs(v) for v in row)
        scale = (wmax / 127.0) if wmax > 0.0 else 1.0
        scales[r] = scale
        for c in range(cols):
            v = row[c]
            qi = int(round(v / scale))
            qi = -127 if qi < -127 else (127 if qi > 127 else qi)
            q[base + c] = qi & 0xff
            err = v - qi * scale
            max_abs_err = max(max_abs_err, abs(err))
            sq_err += err * err
            sq_val += v * v
    rms_rel = (sq_err / sq_val) ** 0.5 if sq_val > 0.0 else 0.0
    stats.append((name, rows, cols, max_abs_err, rms_rel))
    scale_bytes = scales.tobytes()
    if sys.byteorder != 'little':
        scale_bytes = array.array('f', scales).byteswap().tobytes()
    return bytes(q), scale_bytes


def quantize(model):
    """Walk the fp32 checkpoint in exactly memory_map_weights() order and
    replace each weight matrix with (int8 rows, fp32 row-scales); rmsnorm
    tensors pass through unquantized, matching upstream runq.c's choice.
    """
    keys = ["dim", "hidden_dim", "n_layers", "n_heads", "n_kv_heads", "vocab_size", "seq_len"]
    cfg = dict(zip(keys, struct.unpack("<7i", model[:28])))
    dim, hd, L, nh, nkv, V, SL = (cfg[k] for k in keys)
    shared = V > 0
    Vabs = abs(V)
    head_size = dim // nh
    kv_dim = head_size * nkv

    floats = array.array('f')
    floats.frombytes(model[28:])
    if sys.byteorder != 'little':
        floats.byteswap()

    idx = [0]

    def take(n):
        s = floats[idx[0]:idx[0] + n]
        idx[0] += n
        return s

    tok_emb  = take(Vabs * dim)
    rms_att  = take(L * dim)
    wq       = take(L * dim * dim)          # L layers of (dim, dim), d=dim n=dim
    wk       = take(L * kv_dim * dim)       # L layers of (kv_dim, dim)
    wv       = take(L * kv_dim * dim)
    wo       = take(L * dim * dim)
    rms_ffn  = take(L * dim)
    w1       = take(L * hd * dim)           # L layers of (hd, dim)
    w2       = take(L * dim * hd)           # L layers of (dim, hd)  -- cols=hd here
    w3       = take(L * hd * dim)
    rms_final = take(dim)
    idx[0] += SL * head_size // 2 * 2       # skip freq_cis real/imag, unused by run.c
    if not shared:
        take(Vabs * dim)                    # separate wcls -- not needed for stories260K
        raise NotImplementedError("non-shared classifier not exercised by stories260K; "
                                   "wire up a wcls quantize_tensor() call here if this ever fires")
    if idx[0] != len(floats):
        print(f"  WARNING: {len(floats) - idx[0]} trailing floats unaccounted for", file=sys.stderr)

    stats = []
    out = bytearray()
    out += model[:28]                                    # Config header, verbatim
    out += struct.pack('<I', Q8_MAGIC)

    def add_quantized(name, values, rows, cols):
        q, s = quantize_tensor(values, rows, cols, name, stats)
        out.extend(q)
        out.extend(s)

    def add_fp32(values):
        b = array.array('f', values)
        if sys.byteorder != 'little':
            b.byteswap()
        out.extend(b.tobytes())

    # token_embedding_table doubles as wcls (shared_weights=1 for stories260K):
    # quantizing it once here covers both the embedding lookup (dequant one row
    # per token) and the final classifier matmul (packed dot product per row).
    add_quantized("tok_emb/wcls", tok_emb, Vabs, dim)
    add_fp32(rms_att)
    add_quantized("wq", wq, L * dim, dim)
    add_quantized("wk", wk, L * kv_dim, dim)
    add_quantized("wv", wv, L * kv_dim, dim)
    add_quantized("wo", wo, L * dim, dim)
    add_fp32(rms_ffn)
    add_quantized("w1", w1, L * hd, dim)
    add_quantized("w2", w2, L * dim, hd)
    add_quantized("w3", w3, L * hd, dim)
    add_fp32(rms_final)

    print(f"  quantization error, per tensor (max |err|, RMS relative):")
    for name, rows, cols, max_err, rms_rel in stats:
        print(f"    {name:12s} {rows:4d} x {cols:<4d}  max_err={max_err:.5f}  rms_rel={rms_rel:.4%}")

    return bytes(out)


def main():
    q8 = "--q8" in sys.argv[1:]
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

    if q8:
        print("\n  --q8: quantizing to int8 weights (per-row scale, no zero-point) ...")
        q8_blob = quantize(model)
        for d in (EMBED, DIST):
            emit(os.path.join(d, "model260k_q8.h"), q8_blob, "model260k_q8",
                 "stories260K.bin (int8, per-row scale)")
        print(f"  q8 blob  {len(q8_blob)/1024:8.1f} KB  (was {len(model)/1024:.1f} KB fp32, "
              f"{len(model)/len(q8_blob):.2f}x)")


if __name__ == "__main__":
    main()
