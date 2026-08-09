# PRD — vibe-silicon

**Product:** A language model running on a processor we synthesized into an FPGA,
with the Verilog written by an LLM and its quality measured.

**Event:** Sundai Hack 135 — Foundation Models for the Physical World
**Date:** Sunday, August 9 2026 · Boston
**Demo:** 20:00 · **Freeze:** 19:00

---

## Team

| | | |
|---|---|---|
| **Wilson Wu** | Founder & CEO, Dubbs Capital · CRO, Snappy · Owner-operator, Union Made Apparel · MSCS in progress, Georgia Tech OMSCS | [linkedin.com/in/wilson1wu](https://www.linkedin.com/in/wilson1wu/) · [@wilsonwu-ai](https://github.com/wilsonwu-ai) |
| **Justin Pacella** | Software Engineer, Agentic Highway · Northeastern University | [linkedin.com/in/jtp75](https://www.linkedin.com/in/jtp75/) · [@jtp75](https://github.com/jtp75) |

> Titles above are from public sources — LinkedIn blocks automated reads (HTTP 999).
> Correct them directly if either is wrong.

---

## The one-sentence product

> The board has no processor. We put one there, taught it to read, and it wrote a
> story.

## Why anyone should care

Everyone demos a model running on someone else's silicon. We are demoing a model
running on silicon we configured ourselves — no ARM core, no operating system, no
vendor CPU. And the hardware description was written by an LLM, which we grade.

---

## The hard constraint that shapes everything

**Quartus has never had a macOS build — for any version, any edition.** Not
synthesis, not even programming.

Therefore:

- **Justin's PC is the only machine that can touch the board.** Full stop.
- **Wilson's Mac never programs the FPGA.** It writes code, generates artifacts,
  runs the benchmark, and ships the website.

This is not a preference. It is a property of the toolchain, and it determines the
entire split below.

```
   Wilson (macOS, M4 Max)                     Justin (PC, Quartus)
   ───────────────────────                    ─────────────────────
   C code + embedded model  ──── git ────►    compiles for the soft core
   Verilog from LLMs        ──── git ────►    synthesizes onto the FPGA
   benchmark harness                          board + JTAG
   web app + tunnel         ◄─── LAN ─────    token stream out of the board
```

**The interface between them is this git repo plus one HTTP POST.** Nothing else.

---

## Scope

### In scope

1. A soft RISC-V core (NEORV32) synthesized onto the MAX 10, wired to the 64 MB SDRAM.
2. `stories260K` compiled for that core, weights embedded in the binary.
3. Tokens streaming out over JTAG and onto a public web page.
4. A benchmark of LLM-written Verilog: lint → simulate → testbench → synthesize.

### Out of scope — decided, do not relitigate

| Not doing | Why |
|---|---|
| `stories15M` | 97 MB fp32 vs 64 MB SDRAM. Does not fit. |
| `adam-maj/tiny-gpu` | 256-byte memory, simulation-only, no C compiler. See [WHY-KARPATHY.md](WHY-KARPATHY.md) |
| `deaneeth/tiny-gpu` | A Python simulator. Not hardware. |
| Nios V/m | Base RV32I only — no hardware multiply. Wrong tool. |
| Training anything | The hack's own brief says start from a pretrained model. |
| Wilson programming the board | Impossible on macOS. |

---

## Hardware of record

Terasic **DE10-Lite** · Intel MAX 10 **`10M50DAF484C7G`** — identified from
photographs of the silkscreen and die marking.

| | |
|---|---|
| Logic | 49,760 LEs |
| Multipliers | 144 × 18×18 (splittable to 288 × 9×9) |
| On-chip RAM | 1,638 Kbit ≈ 205 KB |
| External RAM | 64 MB SDRAM |
| I/O | VGA, 40-pin GPIO, Arduino headers, ADXL345, 10 switches, 10 LEDs, 6× 7-seg |
| **Absent** | **no ARM, no Linux, no ethernet, no SD card, no filesystem** |

Confirmed working: the on-board USB-Blaster enumerates over USB
(Altera `0x09FB` / `0x6001`).

---

## Model of record

`karpathy/tinyllamas` → **`stories260K`**

| | |
|---|---|
| Config | dim 64 · hidden 172 · 5 layers · 8 heads (4 KV) · vocab 512 · ctx 512 |
| Weights | 1,056,540 bytes fp32 · ~276 KB int8 |
| MACs / token | 259,328 (weights) + 640×(t+1) (attention) |
| Footprint | 1.7 MB of 64 MB = **2.6%** |
| Expected | **0.1 – 3.0 s/token** depending on core config |

---

# Who does what

## Wilson — software, artifacts, and the ship

Wilson cannot run Quartus and will not try. Everything below runs on a Mac and is
handed to Justin through the repo.

| # | Deliverable | Done when |
|---|---|---|
| W1 | **Embedded model artifacts** — `embed/model260k.h`, `embed/tok512.h` | ✅ done. 8-byte aligned, 1,056,540 + 6,227 byte payloads |
| W2 | **`runi.c`** — llama2.c with every filesystem call removed, reading from the embedded arrays instead of `fopen`/`mmap` | compiles clean with `gcc` on macOS **and** produces byte-identical output to upstream `run.c` |
| W3 | **Fixed-point fallback** — integer-only inference, in case software floating point is too slow on the core | generates coherent text on the Mac; only needed if W2 is slow on hardware |
| W4 | **Verilog benchmark harness** | rows in `bench/results/results.jsonl` across ≥3 models × 3 tasks |
| W5 | **Web app + Cloudflare tunnel** — public page showing the live token stream and tokens/sec | reachable from a phone on cellular, not just the venue wifi |
| W6 | **Ingest endpoint** — `POST /tokens` for Justin's PC to push output to | returns 200 from Justin's machine over the venue LAN |
| W7 | **The narrative** — what gets said at 20:00, in what order | rehearsed once, out loud, before 19:30 |

**W2 is the critical path.** Justin cannot compile anything for the core until a
filesystem-free C program exists.

## Justin — hardware, toolchain, and the board

| # | Deliverable | Done when |
|---|---|---|
| J1 | **Toolchain check** — `jtagconfig` sees the board; report the **Quartus version number** | version posted in Discord. If ≥ 24.1std, Nios II does not exist and NEORV32 is the only path |
| J2 | **NEORV32 SoC** — core + SDRAM controller + JTAG UART, pinned for the DE10-Lite | "hello world" prints over JTAG UART |
| J3 | **RISC-V GCC** installed, compiling for the core | W2's C file builds for the target |
| J4 | **Model on the core** — link the embedded arrays, run inference | one token appears |
| J5 | **Token forwarding** — read JTAG UART, POST to Wilson's endpoint | tokens appear on the public page |
| J6 | *(stretch)* **int8 MAC array** replacing `matmul()` | tokens/sec measurably higher than J4 |
| J7 | *(stretch)* **7-segment readout** — live token or MAC count | visible from the audience |

**J2 is the critical path.** Everything hardware-side is blocked behind a working
SoC.

### The economics Justin should know

Synthesis costs ~25 minutes. But **once the SoC is synthesized once, the C program
reloads over JTAG in seconds with no re-synthesis.** So this is not a
twelve-runs-a-day budget — it is one or two runs to get a working SoC, then
unlimited fast iteration in software.

Get the SoC right. Then live in C.

---

## Schedule

| Time | Gate | Owner |
|---|---|---|
| 14:00 | `jtagconfig` sees board; Quartus version reported; W2 compiles on Mac | both |
| 16:00 | **Hard gate.** Soft core prints "hello" over JTAG. If not → fall back | Justin |
| 17:00 | Model emitting tokens on the core; web page live on a tunnel | both |
| 18:00 | Tokens flowing board → PC → Mac → public URL, end to end | both |
| 19:00 | **Freeze.** Deploy whatever exists. No new features. | Wilson |
| 19:30 | Rehearse out loud, once | both |
| 20:00 | Present | both |

## Kill criteria

Written down now so they are not argued about at 18:00 under stress.

1. **16:00 — no "hello world" over JTAG** → abandon the soft-core path. Ship the
   Verilog benchmark plus a hardware MAC array demo on the 7-segments.
2. **17:30 — no tokens on hardware** → present the model running on the Mac beside
   the synthesized core running *something*, and be honest about where the line is.
3. **19:00 — anything not deployed** → cut it. A smaller true demo beats a larger
   broken one.

## Acceptance criteria for the demo itself

- [ ] Reachable at a public https URL from a phone on cellular
- [ ] A token appears on screen, live, from the board
- [ ] Tokens/sec is displayed and honest
- [ ] "Built at Sundai" and both team members credited on the page
- [ ] The repo is public with a license
- [ ] Nobody claims we ran a "real LLM on an FPGA" — we ran a 292K-parameter
      transformer on a soft core, and that is the interesting true thing

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| SDRAM controller timing won't close | medium | It's the #1 failure on this board. Use Terasic's reference config verbatim; don't hand-tune. |
| Software floating point too slow | medium | W3 fixed-point port, already scoped |
| Quartus ≥ 24.1 kills Nios II | medium | NEORV32 is the plan anyway; it's license-free and version-agnostic |
| Synthesis eats the afternoon | medium | One SoC build, then iterate in C over JTAG |
| Venue wifi blocks the LAN POST | low | Fall back to Justin screen-sharing the JTAG terminal into the page |
| **Theme fit** — no foundation model *sensing the physical world* | **high** | See below |

### The theme-fit risk, stated plainly

The hack's stated pattern is **Sensor → Foundation Model → Decision → Physical
Action**. As scoped, this project has a language model but no *sensor* and no
*physical action*.

Cheapest fix, if there's time after 17:00: the board has an on-board **ADXL345
accelerometer**. Read it from the soft core, and let motion seed or steer
generation — tap the board, the story changes. That closes the loop with maybe
thirty lines of C and no extra hardware.

Low priority against shipping, but it is the difference between "on theme" and
"impressive but adjacent."

---

## Definition of done

A stranger opens a URL on their phone, sees words appearing one at a time, and is
told those words are being computed by a processor that did not exist this morning.
