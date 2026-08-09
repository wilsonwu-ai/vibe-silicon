# vibe-silicon

**We synthesized a CPU into an FPGA and ran a language model on it.**
No ARM. No operating system. The entire computer is fabric we generated — and the
Verilog was written by an LLM.

Sundai Hack 135 — Foundation Models for the Physical World (Aug 9, 2026)

### ▶ Live demo — **https://vibe-silicon.wilson-af8.workers.dev**

Streams tokens from the board as they are generated. When the board is not
running it plays the verified host output instead, **labelled as a recording** —
the page never claims a replay is live.

---

> **Hardware correction, 2026-08-09 midday.** This repo originally targeted a
> DE10-**Nano** (Cyclone V, dual-core ARM, boots Linux). The board actually on the
> table is a DE10-**Lite** — MAX 10 `10M50DAF484C7G`, identified from photographs
> of the silkscreen and die marking. It has **no ARM core, no Linux, no ethernet,
> and no SD card**. The plan below is the rewrite. See
> [`board/README.md`](board/README.md) for the full bring-up.

---

## What the board is

| | |
|---|---|
| FPGA | Intel MAX 10 `10M50DAF484C7G` |
| Logic | 50 K logic elements |
| On-chip RAM | 1,638 Kbit M9K ≈ **205 KB** |
| Multipliers | **144 × 18×18** |
| External RAM | **64 MB SDRAM** |
| Human I/O | 10 switches, 10 LEDs, six 7-segment displays, VGA, 40-pin GPIO, ADXL345 |

No ARM. No Linux. No filesystem. That constraint is the project.

## Why the Lite makes a better story than the Nano would have

On a DE10-Nano, a hard ARM processor runs the model and the FPGA sits next to it
doing a matrix multiply. The computer was always there; we would only be renting a
corner of it.

On a MAX 10 there is **no processor at all** until we build one. We place a soft
CPU into the fabric, give it 64 MB of SDRAM, compile a transformer for it, and it
writes a story. Every gate between the power rail and the text is something we put
there.

## The model

`stories260K` — Karpathy's smallest TinyStories checkpoint.

| | params | fp32 | int8 | MACs / token | verdict |
|---|---|---|---|---|---|
| **stories260K** | 292 K | **1.03 MB** | 0.29 MB | **0.26 M** | ✅ ships |
| stories15M | 24.4 M | 97 MB | 24.4 MB | 15.2 M | ❌ exceeds 64 MB SDRAM in fp32 |

`stories15M` is not "too slow", it is too **big** — 97 MB of fp32 weights against
64 MB of SDRAM, because its 32,000-entry embedding table dominates. `stories260K`
is `dim=64, 5 layers, 8 heads, vocab=512` and uses **2.6 % of the board's memory**,
runtime state included.

It also writes real sentences:

> *Once upon a time, there was a little girl named Lily. She loved to play outside
> in the sun.*

## Architecture

```
        embed/model260k.h   (weights as a C array — there is no filesystem)
        embed/tok512.h
                  │
                  ▼
   ┌───────────────────────────────────────────┐
   │  MAX 10 fabric (50K LE, 144 multipliers)  │
   │                                           │
   │   soft RISC-V core  ──►  SDRAM ctrl ──► 64 MB SDRAM
   │        │                                  │
   │        └──► int8 MAC array  ◄─ LLM-written Verilog
   │        │                                  │
   │        └──► JTAG UART ──► tokens          │
   └───────────────────────────────────────────┘
                  │
                  ▼   (Justin's machine, over the venue LAN)
          web UI + cloudflared tunnel   (Wilson's laptop)
```

**Quartus does not run on macOS.** Synthesis is Justin's machine only. That fixes
who does what for the whole day.

## Two deliverables, one pipeline

1. **A language model running on hardware we generated.** Tokens/sec on a soft core
   we placed into fabric, with the inner `matmul()` optionally handed to a
   dedicated int8 MAC array.
2. **A benchmark: how good are current LLMs at writing synthesizable Verilog?**
   Every generated module is logged — did it lint, simulate, pass its testbench,
   synthesize, and at what resource cost.

The second is insurance. If the SoC fights us, the benchmark still ships, and the
three benchmark tasks (`int8_mac`, `dot4_int8`, `mac_array8`) are the accelerator's
own building blocks — so benchmarking *is* building.

## Repo layout

```
board/      DE10-Lite bring-up: toolchain, model, soft core, kill criteria
bench/      LLM-writes-Verilog benchmark harness
  tasks/    one directory per task: spec.md + tb.v
  results/  results.jsonl (append-only)
embed/      model260k.h, tok512.h — the model compiled into the binary
tools/      embed_model.py
rtl/        the accelerator (LLM-generated, human-reviewed)
web/        the demo page
docs/       GLOSSARY.md, ELI5.md, LOG.md, PRD.md, WHY-KARPATHY.md
```

**Read these first:**

| doc | what it answers |
|---|---|
| **[docs/GLOSSARY.md](docs/GLOSSARY.md)** | **every term and acronym, for readers new to hardware — start here** |
| [docs/LOG.md](docs/LOG.md) | play-by-play of the day, including the wrong turns |
| [bench/FINDINGS.md](bench/FINDINGS.md) | benchmark results — and why the headline number should not be quoted |
| [docs/PRD.md](docs/PRD.md) | who does what, schedule, kill criteria, acceptance |
| [docs/WHY-KARPATHY.md](docs/WHY-KARPATHY.md) | why Karpathy's model and not the two `tiny-gpu` repos |
| [docs/ELI5.md](docs/ELI5.md) | all of it in plain English, from "what is an FPGA" |
| [board/README.md](board/README.md) | DE10-Lite bring-up and the soft-core decision |
| [board/WINDOWS-SETUP.md](board/WINDOWS-SETUP.md) | getting a second Windows machine compiling |

## Quickstart

**Benchmark — no board required, runs on any laptop:**

```bash
brew install icarus-verilog verilator
pip install anthropic
python3 bench/harness.py --trials 3
```

**Regenerate the embedded model:**

```bash
python3 tools/embed_model.py
```

**Board bring-up:** [`board/README.md`](board/README.md).

## Schedule

| Time | Gate | Owner |
|---|---|---|
| 14:00 | `jtagconfig` sees the board. Benchmark producing rows. | Justin / Wilson |
| 16:00 | Soft core running *any* C program, printing over JTAG. **If not, fall back.** | Justin |
| 17:00 | Model generating tokens on the core. Web page live on a tunnel. | Justin / Wilson |
| 19:00 | Deployed. Freeze whatever exists. | Wilson |
| 19:30 | Rehearse. | both |

**The economics that matter:** synthesis costs ~25 minutes, but once the SoC is
synthesized *once*, the C program reloads over JTAG in seconds with no
re-synthesis. So this is not a 12-runs-per-day budget — it is one or two runs to
get a working SoC, then unlimited fast iteration in software.

Every Verilog module still simulates in `iverilog` before consuming a synthesis
slot. Simulation is ~1 second and free.

## Fallback, in order

1. Soft core + `stories260K` generating tokens on fabric. ← the goal
2. Soft core running any C, plus a hardware int8 MAC array verified on the
   7-segment displays.
3. The Verilog benchmark alone, with resource/synthesis data. Ships from a laptop.

## License

MIT.

---

**Built at [Sundai Club](https://www.sundai.club) — Hack 135, August 9 2026.**
**Justin Pacella** — Software Engineer, Agentic Highway · Northeastern
[LinkedIn](https://www.linkedin.com/in/jtp75/) · [@jtp75](https://github.com/jtp75)

**Wilson Wu** — B2B SaaS / OMSCS GaTech / Duke MBA
[LinkedIn](https://www.linkedin.com/in/wilson1wu/) · [@wilsonwu-ai](https://github.com/wilsonwu-ai)
