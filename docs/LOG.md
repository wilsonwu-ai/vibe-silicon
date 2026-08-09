# Play-by-play — Sundai Hack 135, Sunday 9 August 2026

The honest record of what actually happened, in order, including the parts that
were wrong. Timestamps are real; they come from the git history and the session.

The interesting entries are the wrong turns. A build log that only records
successes is a press release.

---

## 11:44 — The repo starts out targeting the wrong board

First scaffold committed: *"LLM-written Verilog accelerator for llama2.c on
DE10-Nano."* Plan was to run a transformer on the DE10-Nano's ARM core under
Linux, then move the inner matrix multiply into FPGA fabric and measure the
speedup.

Everything about that plan was reasonable. It was also aimed at hardware nobody
in the room had.

## 11:50 — Photographs kill the plan

Wilson sent three photos of Justin's board. The silkscreen reads **DE10-Lite**
and the die is marked **`10M50DAF484C7G`**.

That is an Intel MAX 10 — a *pure* FPGA. Not an SoC FPGA.

- ❌ no ARM Cortex-A9
- ❌ no Linux
- ❌ no ethernet
- ❌ no SD card, therefore **no filesystem at all**

Every instruction in the repo that began "boot Linux and run the binary" was
describing a different product. `board/README.md` was rewritten from scratch.

**Lesson:** thirty seconds of looking at the actual hardware invalidated two
hours of planning. Do that first.

## 11:50 — The model dies too, and not for the reason expected

The plan called for `stories15M`. Measured against the real files:

| | params | fp32 | MACs/token | verdict |
|---|---|---|---|---|
| stories260K | 292 K | **1.01 MiB** | 259,328 | ✅ |
| stories15M | 15.2 M | **58.0 MiB** | 15.2 M | ❌ |

`stories15M` is not too slow. It is **too big** — 60,816,028 bytes of weights
against 64 MiB of SDRAM, which is 90.6% of it before the program, the stack, or
the model's own 3.5 MB KV cache. Most of its size is a 32,000-entry vocabulary
table against our 512.

> **Corrected 13:30.** This entry originally read "24.4 M params, 97 MB, does not
> fit". Both numbers were wrong and the conclusion was overstated. Checked against
> the actual checkpoint header on HuggingFace: `dim 288 · hidden 768 · 6 layers ·
> 6 heads · vocab 32,000 · ctx 256`, file size 60,816,028 bytes = 15.2 M params.
> It **does** fit in 64 MiB — with ~6 MiB left for everything else, which is why
> it is still dead. Say "fits with nothing left over", not "does not fit": the
> checkpoint is public and the file size is one click away.

`stories260K` uses **2.6%** of the board including runtime state, and writes
readable prose.

## 12:00 — No filesystem means the model becomes source code

`run.c` opens the checkpoint with `fopen`/`mmap`. There is no disk, and no
concept of a file. So the weights were emitted as a C array and linked into the
binary — the model is not *loaded*, it is *part of the executable*.

## ~12:05 — A tip that had to be turned down

A Sundai speaker suggested [`adam-maj/tiny-gpu`](https://github.com/adam-maj/tiny-gpu)
and `deaneeth/tiny-gpu`. Both were read properly before being ruled out:

- `adam-maj/tiny-gpu` is a real GPU in Verilog, and very close to Justin's
  original pitch — but its data memory is **256 bytes** against our 1,056,540-byte
  model, it has **never been synthesized** (behavioural memory, iverilog/cocotb
  only), and its custom 11-instruction ISA has no C compiler.
- `deaneeth/tiny-gpu` is a **Python simulator**. Not hardware, and not a fork of
  the first.
- Neither is Karpathy's. Same naming vibe, unrelated projects.

Written up in [`WHY-KARPATHY.md`](WHY-KARPATHY.md). Kept as a genuine alternative
project rather than merged into this one.

## 12:19 — Quartus 25.1: Nios II no longer exists

Justin reported **Quartus Prime 25.1std Lite**. Intel removed the Nios II IP core
at 24.1std. So the soft core we planned to use was not on his machine and could
not be installed into that version.

Version boundaries that decided the afternoon:

| version | Nios II | Windows toolchain |
|---|---|---|
| **18.1 Lite** | ✅ | ✅ self-contained (bundled Cygwin) |
| 19.1 – 23.1std | ✅ | ⚠️ needs **WSL 1** — WSL 2 unsupported — + Ubuntu 18.04 |
| ≥ 24.1std | ❌ removed | — |

He started a 5 GB+ download of 18.1.

## 12:10 — The best decision of the day: stop building an SoC

Research came back and removed the three things that kill FPGA hackathon
projects. Intel's FPGA University Program ships a prebuilt **"DE10-Lite
Computer"** bitstream containing a **Nios II/f core with hardware floating
point**, an **SDRAM controller mapping all 64 MB**, and a **JTAG UART**.

Programming it takes ~10 seconds. No Platform Designer, no hand-written SDRAM
controller, no timing closure, no synthesis on the critical path.

The FPGA half stopped being *"build a computer"* and became *"program a
known-good computer and compile C for it."* NEORV32 was dropped.

**Lesson:** the highest-leverage move was deleting work, not adding it.

## 12:25 — The port, and the reason it was generated rather than written

`run_baremetal.c` is llama2.c with the operating system removed. It was produced
by a **script** that performs surgical replacements on upstream `run.c`, not
hand-written — so every neural-network function (rmsnorm, softmax, matmul, RoPE,
attention, the sampler) is carried across byte for byte, and the script is the
auditable record of what changed.

That is what earns the right to say *"the math is unmodified"* on stage.

Replaced, and only this: POSIX includes, `read_checkpoint` (blob instead of
mmap), `build_tokenizer`, `malloc_run_state` (static 676 KB arrays), every
remaining `malloc` (96 KB bump allocator, so nothing depends on a bare-metal
heap), `time_in_ms`, and the tok/s `printf` — upstream uses `%f` and newlib's
float printf is enormous.

**Verified byte-identical to upstream**, md5 `8e6e99ed83fc476e1a33bc0940ecffa1`.

## 12:36 — Public page live, three hours before the deadline

Cloudflare Worker + Durable Object at
**https://vibe-silicon.wilson-af8.workers.dev**, with `bridge.py` forwarding the
board's JTAG output.

Deliberately **outbound-only**: the board's host POSTs out over HTTPS, so nothing
listens on the venue network. No inbound port, no tunnel, nothing for conference
wifi to block, and the page survives a laptop sleeping or leaving the building.

This satisfied Sundai's "get off localhost" requirement at 12:36 rather than at
19:00, which meant the project counted regardless of what the board did next.

### Two integrity fixes, made only because someone looked at it

The page rendered fine and said **"LIVE FROM THE BOARD"** — while displaying
*replayed host output*. The page cannot tell where ingested bytes came from. So
`bridge.py` now declares `src=board` or `src=replay` and the page labels itself
accordingly.

Calling a recording "live" is exactly what this project spends its whole README
refusing to do. It would have been an ugly thing to be caught on in Q&A.

Also: the elapsed clock kept counting after generation stopped, silently
inflating elapsed and deflating chars/sec. It now freezes 3 s after the last byte.

## 12:40 — Cloudflare 403s Python

`bridge.py` failed with **HTTP 403, Cloudflare error 1010** — bot protection
rejecting urllib's default `User-Agent`. curl worked, which made it confusing.
Setting any ordinary UA fixes it.

Better to hit that on a Mac at 12:40 than on Justin's machine at 17:00.

## 12:45 — A tarball handed to a Windows user

The handover package was a `.tar.gz`. Justin is on Windows and reasonably asked
what to do with it.

Repackaged as a `.zip`, and `JUSTIN-START-HERE.txt` added — everything ordered by
**when he can actually act on it**, with the two steps that need nothing marked
so the 5 GB install was not dead time.

**Lesson:** a handover package that needs explaining is not finished.

## ~12:55 — GHDL installs, then refuses to run

`brew install ghdl` succeeded, and `ghdl --version` printed **nothing at all**.
It installs as a Homebrew *cask*, so macOS stamps `com.apple.quarantine` on it
and Gatekeeper blocks it — offering to move it to the Trash.

```
xattr -dr com.apple.quarantine /opt/homebrew/Caskroom/ghdl
```

The failure was silent, which is why it went unnoticed at install time. It was
caught only because Wilson hit the dialog himself.

## 13:06 — The benchmark grows a second language

Justin's original pitch was *"how bad are LLMs at writing Verilog / VHDL."*
Measuring the **gap between them** is a stronger result than either alone, and
the literature predicts one: VHDL's verbosity and long-range structural
dependencies produce higher LLM error rates.

A contract was frozen first (`bench/CONTRACT.md`), because an unfair comparison
is worse than none — same circuit, same test vectors, same spec length, no hints
about the failure modes under test. If the VHDL spec were more verbose, the
benchmark would measure the prompt author rather than the models.

## 13:12 — Testbench validation, before any model was benchmarked

Every testbench run against a correct implementation (must pass) and a
deliberately broken one (must fail), where the breakage compiles cleanly and
encodes a real LLM mistake:

| task | planted defect |
|---|---|
| `int8_mac` | reset priority inverted |
| `dot4_int8` | signed inputs treated as unsigned |
| `mac_array8` | blocking assignment in a clocked process |

**12/12 correct**, and both languages discriminate identically — the precondition
for comparing their pass rates at all.

A testbench that passes everything measures nothing.

## ~14:05 — The best idea of the day, and we could not use it

Eugene suggested ternary quantization. It arrived via voice transcription and
came out as *"quantize them turner rate -1 1 and 0 and multiple it by x or gate,
reverse gate and let it through."*

"turner rate" is **ternary**. He was describing BitNet b1.58: constrain every
weight to −1, 0 or +1, and multiplication stops existing — +1 is a wire, −1 is a
sign flip, 0 is an off-switch.

That targets our exact bottleneck. This chip has **144 multipliers and 50,000
logic elements**; ternary needs *zero* multipliers, so it converts our scarcest
resource into our most abundant one.

We did not do it, and the reason is honest: ternary models are trained that way
from scratch. Converting `stories260K` means quantization-aware retraining and
re-validation — a research afternoon, not a hackathon hour, and we already had a
verified path.

Written up in [TERNARY.md](TERNARY.md), labelled as the thing we did **not** do,
with credit to Eugene.

---

## 14:00 — The model runs on the FPGA, and the output is exact

`quartus_pgm` → prebuilt DE10-Lite Computer, configured in 4 seconds. BSP
generated straight from `Computer_System.sopcinfo`, `llama.elf` built with the
model as a C array, downloaded over JTAG in 20 s.

**256 tokens. Byte-identical to `expected_output.txt`.** The soft core and the
macOS host agree exactly, all 574 bytes — the float-divergence worry that the
instructions warn about ("different words = float math") simply did not happen.

The linker-region trap — the one the docs call the single most likely way to lose
an hour — never fired. `nios2-bsp` chose correctly on its own:
`"Default linker sections mapped to SDRAM"`. Verified by section *address*
(`.rodata` at `0x21028`, on-chip SRAM at `0x08000000` holding nothing) rather
than by trusting a dialog.

## 14:05 — Two surprises in a bitstream we thought we understood

**The prebuilt system is dual-core.** Two Nios II, two JTAG UARTs, and no `.jdi`
to disambiguate them — so `nios2-download` and `nios2-terminal` refuse to connect
at all until given `--device 1 --instance 0`. Nothing in the plan mentioned a
second core.

**A run that looked exactly like the documented failure was not one.** Output
appeared to stall at 434 of 578 bytes and sat frozen for 90 seconds — textbook
"stops early". An instrumented build printed `<LOOP-EXIT pos=256 steps=256>` and
the complete story: the program was fine, the *capture* had stopped. Diagnose the
output path before believing a hang.

## 14:20 — 1.02 s/token, and the estimate was wrong for an interesting reason

Measured: **1.020 s/token, 0.98 tok/s.** The repo predicted 0.1–0.2 s/token with
the hardware FPU. Off by 5–10×.

The obvious suspect was the FPU flag, and it was innocent — `-mcustom-fpu-cfg=60-2`
is in the generated `public.mk` and the image contains 66 `custom` instructions.
The FPU is working.

The actual cause was sitting in `system.h` the whole time:

```
ALT_CPU_DCACHE_SIZE 0
```

**The core has no data cache.** All ~259,000 weight reads per token go to a
16-bit SDRAM as individual uncached transactions — 357 ns each, measured. A
dependent float multiply-add costs 298 ns. They add rather than overlap, and the
real `matmul` lands at **722 ns per MAC**.

Profiled at 100 MHz (after adding a timestamp timer, because the system clock
ticks at a useless 8 Hz): `matmul` 48 % of `forward()`, `softmax` 28 %,
everything else 22 %.

And `softmax` is expensive for its own reason: `expf`, `powf` and `sqrtf` all
call `__adddf3`/`__muldf3`/`__divdf3`. **newlib promotes them to double, and this
core has single-precision hardware only** — so the exponentials in every softmax
are software-emulated double precision.

**Lesson:** we spent the afternoon protecting against the wrong risk. The danger
was never the FPU flag; it was a cache line in a config file nobody read. The
prebuilt system saved us hours *and* silently set our performance ceiling.

**The honest framing for the slide:** we retire ~334 K MAC/s on fabric that could
do ~28.8 G — about 1/86,000th of the silicon. Not because the multipliers are
missing, but because nothing can feed them. That is the same wall a real
accelerator hits.

---

## Running themes

**Look at the hardware before planning around it.** One photo invalidated hours
of work.

**Deleting work beat adding it.** The prebuilt DE10-Lite Computer removed the
three highest-risk items in one move.

**Every claim got checked rather than asserted.** Byte-identical output, 12/12
discrimination, measured model sizes. The numbers in this repo are measurements.

**The failures were mostly silent.** GHDL printing nothing, Cloudflare's 403,
`.bss` landing in on-chip RAM and hanging with no message. Silence is the
expensive failure mode, which is why the docs call each one out by name.
