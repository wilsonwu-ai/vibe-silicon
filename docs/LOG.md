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
| stories260K | 292 K | **1.03 MB** | 259,328 | ✅ |
| stories15M | 24.4 M | **97 MB** | 15.2 M | ❌ |

`stories15M` is not too slow. It is **too big** — 97 MB of weights against 64 MB
of SDRAM. It does not fit, and most of its size is a 32,000-entry vocabulary
table against our 512.

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
