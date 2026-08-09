# Handoff — for a fresh planning session

Written 2026-08-09, ~15:00. Everything below is verified on real hardware
unless marked otherwise. Read this before re-deriving anything — most of the
open questions in this repo's history are already answered.

## State in one line

**The primary deliverable works.** 256 tokens generated on the FPGA, byte-
identical to the golden reference, 1.020 s/token measured. Two independent
build paths verified end-to-end on the board. What's left is integration
(bridge → public page) and a decision about the accelerator stretch goal.

## Start here

| doc | what it has |
|---|---|
| [`HARDWARE-RESULTS.md`](HARDWARE-RESULTS.md) | every measured number, the profile, why it's 1.02s not 0.1s |
| [`PRD.md`](PRD.md) | status board (J1–J9), scope, out-of-scope decisions — **don't relitigate these** |
| [`LOG.md`](LOG.md) | chronological play-by-play, including wrong turns |
| [`TERNARY.md`](TERNARY.md) | the accelerator idea we're **not** doing, and why |
| `bench/FINDINGS.md` | Verilog-benchmark results, with an honest "don't trust the headline" |

## What's verified working

- Board: DE10-Lite, MAX 10 `10M50DAF484C7G`, confirmed via `jtagconfig`.
- Toolchain: Quartus 18.1 + Nios II EDS, at `C:\intelFPGA_lite\18.1`.
- Prebuilt system: "DE10-Lite Computer" from the University Program, programmed via `quartus_pgm`.
- Model runs, both build paths, both byte-identical to `expected_output.txt`:
  - **Primary**: `model260k.h`/`tok512.h` C arrays, no `.bin`, no objcopy. This is what ships in `dist/llama-nios/`.
  - **Fallback**: `nios2-elf-objcopy` on the real `.bin` files in `models/`. Also verified now — see gotcha below.
- Speed: **1.020 s/token, 0.98 tok/s**, measured with a stopwatch-equivalent (external wall clock — `time_in_ms()` still returns 0 on the board by design).

## Not yet done

| | what | why it matters |
|---|---|---|
| **J8** | `bridge.py` → public Cloudflare page, run against the **live board** (only tested separately: bridge against `--replay`, board against `nios2-terminal` directly) | closes the actual demo path |
| **J9** | insurance: `.sof` + `.elf` on a USB stick / second laptop, phone video of the board generating tokens | what plays if hardware dies at demo time |
| — | power-cycle recovery check | unplug/replug, reprogram `.sof`, rerun — never explicitly tested cold |

## The machine, facts a planner needs

- **Dual-core.** Two Nios II, two JTAG UARTs, no `.jdi` to disambiguate. Every `nios2-download`/`nios2-terminal` call **must** carry `--device 1 --instance 0`, or it refuses to connect.
- **No data cache.** `ALT_CPU_DCACHE_SIZE 0`. This is *the* fact that explains the performance story — every one of ~259,000 weight reads/token is an individual uncached SDRAM transaction (357 ns each, measured).
- **Usable SDRAM region is ~32 MiB, not 64.** The generated linker region is `ORIGIN=0x20, LENGTH=33554400`. Irrelevant at our 1.9 MB footprint; relevant if anyone scales the model up.
- **System clock is 8 Hz.** Useless for profiling. A timestamp timer was added to the BSP (`hal.timestamp_timer Interval_Timer_2`) for 100 MHz resolution — do this again if the BSP is regenerated from scratch.
- **Linker-region trap (the one the docs warn about) does not fire here.** `nios2-bsp` maps everything to SDRAM correctly by default. Verified by section *address*, not by trusting a dialog.

## Gotchas discovered the hard way (don't rediscover)

1. **Stale JTAG UART output.** A previous program keeps running after you close the terminal; its buffered bytes arrive in the *next* session and look like corrupted output. Always `nios2-download -r` then drain with a throwaway terminal before a measured run.
2. **A capture stall isn't necessarily a board hang.** One run looked frozen at 434/578 bytes for 90s — looked exactly like the documented "stops early" failure. It wasn't; the capture had stopped, not the board. Confirm the output *path* before declaring a hang.
3. **objcopy fallback: GP-relative overflow.** Linking `model.o`+`tok.o` (~1 MB extra) as separate objects can push something out of the ±32K global-pointer range the prebuilt BSP assumes (`-mgpopt=global`). Fix is regenerating the whole BSP with `-mgpopt=none`, not just recompiling. Only affects the fallback path, not the primary header build.
4. **Only one process can own the USB-Blaster JTAG cable at a time** — Programmer, Monitor Program, `nios2-terminal`, `nios2-download` all conflict. Close others before running.
5. **Only one CPU freq claim is real: 100 MHz**, `impl=Fast` (Nios II/f). FPU is genuinely active (`-mcustom-fpu-cfg=60-2` in `public.mk`, 66 `custom` opcodes in the linked image) — don't waste time re-verifying this.

## Decisions already made — do not relitigate

- **Ternary/BitNet quantization: not worth it.** Kills multiplication (144-multiplier ceiling), but the bottleneck is *memory bandwidth*, not multiply throughput — ternary weights still need one uncached fetch each, same as fp32. Would need retraining + breaks byte-exactness. See `TERNARY.md`.
- **Wiring an int8 MAC array into the live Qsys system / `matmul()`: still no.** Re-introduces the SoC/synthesis risk the PRD dropped, and per the bandwidth finding above wouldn't fix the actual bottleneck — you'd resynthesize the working system and still be memory-bound.
- **Update, superseding the above:** a **standalone, disconnected** hardware proof is in progress — one benchmark module (`mac_array8`) synthesized on its own separate bitstream, driven by switches/LEDs, never touching the DE10-Lite Computer system. This exists purely to make "LLM-written Verilog runs on this chip" literally true on silicon, not just in simulation. It is bonus, not required, and does not put the working model demo at risk. See README's "What's ours, what's Intel's, and what's LLM-written" table.
- **`stories15M`: correctly out of scope.** Fits in 64 MiB (58.0 MiB, 90.6%) but leaves nothing for code/stack/KV-cache. Not "doesn't fit" — "fits with nothing left over."
- **No `rtl/` directory exists yet.** README's repo-layout table lists it as if present; it isn't. If accelerator work is greenlit later, that's where it'd go.

## Free backlog item, not yet done

**Hoist RoPE out of the layer loop.** Upstream calls `powf` 160×/token (`dim/2 × n_layers`) to compute `cos`/`sin` that depend only on `(pos, i)`, not layer — 5× redundant. `powf` measured at 317 µs/call (100× a plain float multiply). Hoisting to 32 calls saves **~40.6 ms/token (~4% of total), zero change to any output byte** — the only optimization on the table that keeps bit-exactness. This is W5 in the PRD backlog.

## Build quick-reference

```
Toolchain: C:\intelFPGA_lite\18.1  (Nios II Command Shell for all nios2-* tools)
Board sof: University_Program\Computer_Systems\DE10-Lite\DE10-Lite_Computer\verilog\DE10_Lite_Computer.sof
Package:   dist/llama-nios/  (self-contained: run_baremetal.c + model260k.h + tok512.h + bridge.py)
Scratch build dir used this session: C:\nios-llama  (BSP, app, bench harnesses — outside the repo)

nios2-download -c "USB-Blaster [USB-0]" --device 1 --instance 0 -g llama.elf
nios2-terminal --device 1 --instance 0
```

## Team constraint, unchanged

Quartus has no macOS build. Justin's PC is the only machine that can touch the
board — full stop. Wilson's side (webapp, benchmark harness, docs) runs
anywhere and is otherwise finished.
