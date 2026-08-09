# vibe-silicon

**We programmed a soft CPU into an FPGA's fabric and ran a language model on it.**
No ARM. No operating system. The processor is Intel's prebuilt Nios II core — not
designed by us, and not LLM-written. See
[what's ours, what's Intel's, and what's LLM-written](#whats-ours-whats-intels-and-whats-llm-written)
below before repeating any claim from this README on stage.

Sundai Hack 135 — Foundation Models for the Physical World (Aug 9, 2026)

> ### ✅ It works — measured on the board
>
> **256 tokens generated on the FPGA. Output byte-identical to the reference.
> 1.020 s/token (0.98 tok/s), measured, not estimated.**
>
> There is no float divergence between the soft core and the macOS host — they
> agree exactly for all 256 tokens. Numbers, profile, and the reason it is 1 s
> and not the 0.1 s we predicted: [`docs/HARDWARE-RESULTS.md`](docs/HARDWARE-RESULTS.md).

### ▶ Live demo — **https://vibe-silicon.wilson-af8.workers.dev**

**Verified end to end on real hardware.** The page has received the full 256-token
story straight off the board over JTAG, byte-identical to the reference
(md5 `8e6e99ed83fc476e1a33bc0940ecffa1`). Evidence: [docs/E2E-VERIFIED.md](docs/E2E-VERIFIED.md)

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

## What's ours, what's Intel's, and what's LLM-written

Four separate things, easy to conflate into one story. They aren't one story.

| | who built it | status |
|---|---|---|
| Nios II core, SDRAM controller, JTAG UART — what actually runs the model | **Intel**, prebuilt ("DE10-Lite Computer", FPGA University Program) | ✅ running |
| Bare-metal C port + getting the model to run on that core | us | ✅ done — byte-identical output, see [HARDWARE-RESULTS.md](docs/HARDWARE-RESULTS.md) |
| Accelerator Verilog (`int8_mac`, `dot4_int8`, `mac_array8`), graded in simulation | Opus 5 / Sonnet 5 / Haiku 4.5, via `bench/harness.py` | ✅ done — see [bench/FINDINGS.md](bench/FINDINGS.md); **headline number not trustworthy**, read the caveats |
| That same accelerator on real silicon — standalone bitstream, switches/LEDs, not touching the model system | LLM-written, human-reviewed | 🔄 in progress |

**We did not design a CPU.** We configured Intel's prebuilt core into fabric that
had none, and wrote the bare-metal software around it.

**The language model does not run through any LLM-written Verilog.** The
accelerator work is a separate, disconnected proof that an LLM-written module
works on real hardware — not an optimization sitting inside the model's compute
path, and not planned to become one: the board is bandwidth-bound, not
compute-bound (no data cache — see HARDWARE-RESULTS.md), so wiring an
accelerator into `matmul()` would not speed up generation even if we built it.

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
| **stories260K** | 292 K | **1.01 MiB** | 0.29 MB | **0.26 M** | ✅ ships |
| stories15M | 15.2 M | **58.0 MiB** | 14.5 MB | 15.2 M | ❌ 90.6 % of SDRAM before anything else |

`stories15M` is not "too slow", it is too **big** — its 32,000-entry embedding
table dominates, and 60,816,028 bytes of fp32 weights is **90.6 % of the 64 MiB
SDRAM on their own**, before code, stack, or its 3.5 MB KV cache. It fits and
leaves nothing over, which is worse than not fitting. `stories260K` is
`dim=64, 5 layers, 8 heads, vocab=512` and uses **2.6 % of the board's memory**,
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
   │   soft Nios II/f core ─►  SDRAM ctrl ──► 64 MB SDRAM
   │        │                                  │
   │        └──► JTAG UART ──► tokens          │
   └───────────────────────────────────────────┘
                  │
                  ▼   nios2-terminal on Justin's PC
             bridge.py ──── outbound HTTPS ────► Cloudflare Worker
                                                 (public page, anyone's browser)
```

This is the complete data path for the model. **There is no accelerator in it** —
`matmul()` runs entirely on the Nios II core, nothing is offloaded. The
LLM-written accelerator lives on a separate, standalone bitstream (see the table
above); it does not appear in this diagram because it is not wired to any of it.

The core is **Nios II/f**, Intel's soft processor — not RISC-V. Nothing listens on
the venue network: the bridge POSTs outward, so there is no inbound port, no
tunnel, and nothing for conference wifi to block.

**Quartus does not run on macOS.** Synthesis is Justin's machine only. That fixes
who does what for the whole day.

## Two deliverables, plus one bonus proof

1. **A language model running on a soft core we programmed into fabric.** The
   core itself is Intel's, prebuilt — see the table above. `matmul()` is not
   handed to anything; it runs entirely on the Nios II.
2. **A benchmark: how good are current LLMs at writing synthesizable Verilog?**
   Every generated module is logged — did it lint, simulate, pass its testbench,
   synthesize, and at what resource cost. Simulation only; see
   [bench/FINDINGS.md](bench/FINDINGS.md) before quoting the headline number.

**Bonus, in progress:** proving one of the benchmark's own modules (`mac_array8`)
on real silicon — a standalone bitstream driven by switches/LEDs, disconnected
from the language-model system in deliverable 1. Not required for either
deliverable above; it exists to make "an LLM wrote Verilog that runs on this
chip" literally true on hardware, not only in simulation.

## Repo layout

```
board/      DE10-Lite bring-up: toolchain, model, soft core, kill criteria
bench/      LLM-writes-Verilog/VHDL benchmark harness
  tasks/    one directory per task: spec.md + tb.v (+ spec_vhdl.md + tb.vhdl)
  results/  results.jsonl (append-only)
embed/      model260k.h, tok512.h — the model compiled into the binary
tools/      embed_model.py
web/        the demo page
docs/       GLOSSARY.md, ELI5.md, LOG.md, PRD.md, WHY-KARPATHY.md, HANDOFF.md
```

**Read these first:**

| doc | what it answers |
|---|---|
| **[docs/HARDWARE-RESULTS.md](docs/HARDWARE-RESULTS.md)** | **what the board actually did, measured — speed, profile, and why it is 1 s/token** |
| **[docs/GLOSSARY.md](docs/GLOSSARY.md)** | **every term and acronym, for readers new to hardware — start here** |
| **[docs/TALK.md](docs/TALK.md)** | **what to say at 8pm — 30-second and 3-minute versions, with the numbers** |
| [docs/E2E-VERIFIED.md](docs/E2E-VERIFIED.md) | proof the public page is fed by real silicon, not a simulator |
| [docs/LOG.md](docs/LOG.md) | play-by-play of the day, including the wrong turns |
| [bench/FINDINGS.md](bench/FINDINGS.md) | benchmark results — and why the headline number should not be quoted |
| [docs/TERNARY.md](docs/TERNARY.md) | Eugene's suggestion: make the multiplier disappear. The best idea we did **not** ship |
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

## Fallback, in order — resolved, kept for the record

1. ✅ Soft core + `stories260K` generating tokens on fabric. ← the goal, and what happened.
2. Soft core running any C, plus a hardware int8 MAC array verified on the
   7-segment displays. **Not needed as a fallback** — #1 succeeded — but being
   built anyway, as a standalone bonus proof, disconnected from the model. See
   the table near the top of this README.
3. ✅ The Verilog benchmark alone, with resource/synthesis data. Ships from a
   laptop regardless of hardware — also done.

## Editing the generation seed

The seed is hardcoded in tools/make_baremetal.py, in the generated main() block — unsigned long long rng_seed = 42;   /* fixed: reproducible on stage */. To change it, edit that literal in the generator script, then regenerate (python tools/make_baremetal.py), copy src/run_baremetal.c to dist/llama-nios/run_baremetal.c, and rebuild via build.sh.

Same rule as the LED change: edit the generator, not run_baremetal.c directly, since the .c file is generated output.

One important consequence: changing the seed changes the output story, so it will no longer byte-match expected_output.txt — that file was captured at seed 42 specifically. If you change the seed you'd need a new reference to verify against (e.g. rerun the host build at the new seed and recapture it), otherwise you lose the byte-exactness check that's been the correctness proof all along.

## License

MIT.

---

**Built at [Sundai Club](https://www.sundai.club) — Hack 135, August 9 2026.**
**Justin Pacella** — Software Engineer, Agentic Highway · Northeastern
[LinkedIn](https://www.linkedin.com/in/jtp75/) · [@jtp75](https://github.com/jtp75)

**Wilson Wu** — B2B SaaS / OMSCS GaTech / Duke MBA
[LinkedIn](https://www.linkedin.com/in/wilson1wu/) · [@wilsonwu-ai](https://github.com/wilsonwu-ai)
