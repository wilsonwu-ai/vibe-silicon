# PRD — vibe-silicon

**Product:** A language model running bare metal on a soft processor we programmed
into an FPGA, with LLM-written Verilog benchmarked alongside it.

**Event:** Sundai Hack 135 — Foundation Models for the Physical World
**Date:** Sunday, August 9 2026 · Boston
**Demo:** 20:00 · **Freeze:** 19:00

---

## Team

| | | |
|---|---|---|
| **Wilson Wu** | B2B SaaS / OMSCS GaTech / Duke MBA | [LinkedIn](https://www.linkedin.com/in/wilson1wu/) · [@wilsonwu-ai](https://github.com/wilsonwu-ai) |
| **Justin Pacella** | Software Engineer, Agentic Highway · Northeastern University | [LinkedIn](https://www.linkedin.com/in/jtp75/) · [@jtp75](https://github.com/jtp75) |

> Justin's title is from public sources — LinkedIn blocks automated reads (HTTP 999).
> Correct it directly if it is wrong.

---

## Status — updated 14:40, Sunday

| | item | state |
|---|---|---|
| W1–W8 | model artifacts, golden reference, `run_baremetal.c`, tarball, webapp, bridge | ✅ **all done** |
| W4 | Verilog/VHDL benchmark | ✅ ran — see [bench/FINDINGS.md](../bench/FINDINGS.md); headline **not** quotable |
| W9 | verbatim stage claim | ⬜ drafted below, needs rehearsing |
| W10 | screen recording | ⬜ 19:00 |
| — | fixed-point / int8 port | ⬜ **now has measured justification** — the core is memory-bound with no data cache, so fewer *bytes* is worth more than faster arithmetic. Costs bit-exactness; team decision |
| — | hoist RoPE out of the layer loop (W5) | ⬜ the one speedup that **keeps** byte-exactness — 5 layers currently recompute identical `cos`/`sin` |
| J1 | Quartus version | ✅ was 25.1std → Nios II absent → 18.1 installed |
| J2 | **Quartus 18.1 working** | ✅ **done** |
| J3 | **board alive, JTAG serial working** | ✅ **done** — board, cable, USB-Blaster driver and toolchain all confirmed |
| J4 | Monitor Program 18.1 + stock sample printing | ✅ **done** — verified e2e with the official guide demo |
| J5 | linker regions in SDRAM | ✅ **done** — the BSP defaults are already correct for this system; verified by section *address*, not by dialog |
| J6 | **build ours and run it** | ✅ **DONE — 256 tokens on the board, byte-identical to the golden reference** |
| J7 | measure s/token | ✅ **done — 1.020 s/token, 0.98 tok/s** (measured, not estimated) |
| J8–J9 | bridge to the public page, insurance | ⬜ |

**The primary path is done.** The model generates all 256 tokens on the FPGA and
the output is byte-identical to the macOS reference — there is no float
divergence between the board and the host. The remaining work is the bridge, the
recording, and the talk; every fallback in this document is now insurance we do
not need.

Measured, and it corrects this document: **1.020 s/token**, not the 0.1–0.2
predicted. The hardware FPU is confirmed active — the core simply has **no data
cache**, so every weight read hits a 16-bit SDRAM uncached. Full numbers in
[HARDWARE-RESULTS.md](HARDWARE-RESULTS.md).

No kill criterion was ever triggered at any point today. The fallback — a custom
RTL MAC array plus WASM in the browser — was never needed. This is against a repo
that at 11:44 this morning was aimed at a DE10-Nano, a board nobody in the room
had.

---

## The one-sentence product

> The board has no processor. We put one there, gave it a language model, and it
> wrote a story.

## Why anyone should care

Everyone demos a model running on someone else's silicon. We are demoing a model
running on a processor that did not exist until we configured it into fabric — no
ARM, no operating system, no filesystem. And separately, we grade how well LLMs
write the Verilog such a machine is made of.

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
   Verilog from LLMs        ──── git ────►    graded in simulation only
   benchmark harness                          (not programmed onto the board —
                                                the model's soft core carries
                                                no LLM-written Verilog; see
                                                README's ownership table)
   web app on Cloudflare    ◄── HTTPS ─────   bridge.py POSTs tokens outbound
```

The token path does **not** cross the venue LAN and does not touch Wilson's
laptop: `bridge.py` POSTs straight to the Worker. No inbound port, no tunnel,
nothing for conference wifi to block, and the page stays up if Wilson's laptop
sleeps or leaves.

**The interface between them is this git repo plus one HTTP POST.** Nothing else.

---

## Scope

### In scope

1. The prebuilt **DE10-Lite Computer** (Nios II/f + FPU + SDRAM controller + JTAG UART) programmed onto the MAX 10.
2. `stories260K` compiled for that core, weights embedded in the binary.
3. Tokens streaming out over JTAG and onto a public web page.
4. A benchmark of LLM-written Verilog: lint → simulate → testbench → synthesize. **Simulation only** — nothing from the benchmark is synthesized onto the board as part of this scope.

**Bonus, not required for either deliverable above:** one benchmark module
(`mac_array8`) proven on real silicon — a separate, standalone bitstream driven
by switches/LEDs, not touching the DE10-Lite Computer system or `matmul()`.
In progress. If it does not land, nothing above is affected.

### Out of scope — decided, do not relitigate

| Not doing | Why |
|---|---|
| `stories15M` | 15.2 M params, **58.0 MiB** fp32 — 90.6% of the 64 MiB SDRAM on its own, before code, stack, or a 3.5 MB KV cache. It technically fits and is still unusable. See kill criterion 9. |
| `adam-maj/tiny-gpu` | 256-byte memory, simulation-only, no C compiler. See [WHY-KARPATHY.md](WHY-KARPATHY.md) |
| `deaneeth/tiny-gpu` | A Python simulator. Not hardware. |
| Building an SoC in Platform Designer | Unnecessary — a prebuilt, pre-verified one exists. |
| NEORV32 / Nios V/m | Superseded by the prebuilt image. Nios V/m is RV32I only anyway — no hardware multiply. |
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
| ~~Expected~~ | ~~0.1–0.2 s/token with hardware FPU — *derived*~~ — **wrong by 5–10×** |
| **Measured** | **1.020 s/token · 0.98 tok/s** — 256 tokens in 261 s, output byte-identical to the reference. Hardware FPU confirmed active. See [HARDWARE-RESULTS.md](HARDWARE-RESULTS.md) |

---

# Who does what

> **Plan change, verified midday.** We are **not** building an SoC. Intel's FPGA
> University Program ships a prebuilt **"DE10-Lite Computer"** bitstream (inside the
> Intel FPGA Monitor Program) containing a **Nios II/f core with hardware floating
> point**, an **SDRAM controller mapping all 64 MB at `0x00000000`**, and a **JTAG
> UART at `0xFF201000`**. Programming it takes ~10 seconds. No Platform Designer, no
> SDRAM timing closure, no synthesis — the three things that kill FPGA hackathon
> projects are all removed from the critical path.

## Wilson — software, artifacts, and the ship

| # | Deliverable | Done when |
|---|---|---|
| W1 | **Embedded model artifacts** — `embed/model260k.h`, `embed/tok512.h` | ✅ done. Byte counts verified: 1,056,540 and 6,227 |
| W2 | **Golden reference** — run `stories260K` on macOS at **seed 42, temperature 1.0, top-p 0.9** (upstream defaults; determinism comes from the fixed seed, not from temp 0 — the shipped code does not use temp 0) | saved. It is both the bit-exactness reference and the webapp's replay stream |
| W3 | **`run_baremetal.c`** — delete `read_checkpoint`'s entire mmap/fopen/fread/fseek/ftell path, point `weights_ptr` at the linked blob, replace every malloc/calloc with static arrays (working set is 676,192 B), stub `time()` | byte-identical output to W2, compiled with clang on macOS |
| W4 | **Two details that decide whether it looks alive** | (a) `setvbuf(stdout, NULL, _IONBF, 0)` or tokens arrive in one block at the end and the board looks dead for 30 s; (b) print with `fputs`/`putchar`, **never `%f`** — newlib's float printf is enormous |
| W5 | **Precompute the RoPE `powf()` table** — loop-invariant across tokens, and one of the two software-float hot spots | measurable speedup, or dropped if the FPU flag works |
| W6 | **Package for Justin** — `dist/llama-nios/`: `run_baremetal.c`, `model260k.h`, `tok512.h`, `expected_output.txt`, `bridge.py`, and JUSTIN-START-HERE.txt | handed over by 14:45. **No `.bin` files and no `objcopy` step** — the weights ship as the aligned C arrays, which removes both the symbol-name trap and an unaligned-`float*` failure that would have produced a *wrong story rather than a crash* on Nios II |
| W7 | **Public webapp** — Cloudflare Worker + Durable Object on `*.workers.dev`: `POST /ingest` (bearer token), SSE `GET /stream`, live tokens + tok/s counter | live by 15:30, verified from a phone **on cellular**, not venue wifi |
| W8 | **`bridge.py`** — stdlib only, ~40 lines: spawn `nios2-terminal`, read stdout char by char, POST batched chars every 250 ms | sent to Justin by 16:15. Outbound HTTPS only — no inbound port, no tunnel |
| W9 | **The exact stage claim, written verbatim** before 18:00 | see "What we say" below |
| W10 | **Screen recording** of the live page streaming real tokens | exists by 19:00. This is what plays if anything dies at 20:00 |

**W3 is the critical path.** Justin cannot compile anything until it exists.

## Justin — toolchain and the board

| # | Deliverable | Done when |
|---|---|---|
| J1 | **Three answers, first 15 minutes, nothing else** | (a) Quartus version from *Help → About*, (b) does `jtagconfig` list the `10M50`, (c) does `nios2-elf-gcc --version` work |
| J2 | **Quartus Prime Lite 18.1** if Nios II EDS is missing — *Individual Files* tab: base ~1.7 GB + `max10-18.1.0.625.qdz` ~331 MB, 14 GB disk. Skip ModelSim and every other device family | `nios2-elf-gcc --version` works |
| J3 | **Prove the board is alive independently** — resolve the USB-Blaster driver (lives under `<quartus>/drivers`), program any prebuilt Terasic demo `.sof` | 7-seg or GSensor demo runs |
| J4 | **Monitor Program** → new project → **DE10-Lite Computer** predesigned system → load a bundled sample C program → Compile → Load → Run | output appears in the terminal. **This is the 14:30 gate** |
| J5 | **Linker regions in SDRAM** — `.text`, `.rodata`, `.data`, `.bss`, heap, stack at `0x00000000`, **not** the 64 KB on-chip RAM | 1.7 MB links. Getting this wrong hangs with **no error message** |
| J6 | **Build and run Wilson's tarball** | first 20 tokens match the expected output |
| J7 | **Measure seconds-per-token** and report it | Wilson has a real number by 16:30. Neither of you quotes the estimate |
| J8 | **Run `bridge.py`** against `nios2-terminal` | tokens land on the public URL |
| J9 | **Insurance** — `.sof` + `.elf` on a USB stick and a second laptop; phone video of the board generating tokens | both exist by 19:00 |

### Quartus version is the day's biggest risk

| version | Nios II? | Windows toolchain |
|---|---|---|
| **18.1 Lite** | ✅ | ✅ self-contained — **use this** |
| 19.1 – 23.1std | ✅ | ⚠️ **WSL1** (WSL2 explicitly unsupported) + Ubuntu 18.04 + manual Eclipse — 1–3 hour rabbit hole |
| ≥ 24.1std | ❌ **removed** | Nios II IP no longer exists |

---

## Schedule

| Time | What | Owner |
|---|---|---|
| 12:00–12:15 | Alignment. Justin answers J1's three questions. Lock the install decision. | both |
| 12:15–12:45 | Start the Quartus 18.1 download (skip if Nios II EDS works) | Justin |
| 12:15–13:00 | Golden reference output on macOS, fixed seed | Wilson |
| 12:45–13:30 | USB-Blaster driver, `jtagconfig`, program a Terasic demo | Justin |
| 13:00–14:15 | Write `run_baremetal.c`, verify byte-identical | Wilson |
| 13:30–14:30 | Install Quartus 18.1 + Monitor Program 18.1 | Justin |
| 14:15–14:45 | Package the tarball | Wilson |
| 14:30–15:30 | Build Wilson's tarball for Nios II, download, run | Justin |
| 14:45–15:30 | Deploy the Worker webapp to a public URL | Wilson |
| 15:30–16:30 | Debug and **measure** s/token. Do not optimize past "it works" | Justin |
| 15:30–16:15 | Write `bridge.py`, send to Justin | Wilson |
| **16:30–17:00** | **KILL GATE.** Decide primary vs fallback out loud, one sentence each. Commit. No re-litigating after. | both |
| 17:00–18:00 | Integration: bridge → public URL, watched from a different network | both |
| **18:00** | **HARD FREEZE.** No new compiles, no new features. | both |
| 18:00–19:00 | Slides + narrative / record insurance video | split |
| 19:00–19:45 | Two full timed dry runs. Rehearse the 30-second and 3-minute versions | both |
| 19:45–20:00 | Set up. Public URL open on a second device as proof | both |

## Kill criteria

1. **12:30** — if Quartus is ≥ 24.1 or there is no Nios II EDS, the 18.1 download must be **underway**.
2. **13:45** — `jtagconfig` must list the `10M50`. Not resolved by 14:15 → the board is out; go software-only (WASM in the browser) and show the Verilog benchmark.
3. **14:30** — a **stock** Monitor Program sample must be printing from the board. If not → **abandon the Nios II path**, Justin switches to the RTL MAC array, Wilson starts the emscripten WASM build.
4. **15:30** — the public URL must be live and streaming the **replayed** token stream, verified from a phone on cellular. Sundai requires a deployed webapp; without it the project does not count.
5. **16:30** — the board must have printed at least one real token. Something-but-not-tokens → keep debugging until 17:30, model **frozen** at `stories260K` fp32.
6. **17:30** — tokens on the board but the bridge not delivering → stop fixing the bridge, switch the page to **replay mode**. A recorded real result on a live public page beats a broken live pipe.
7. **18:00** — hard freeze, unconditional.
8. **19:00** — a screen recording of the live page **and** a phone video of the board must both exist. If not, stop rehearsing and make them.
9. **ANY TIME** — if anyone proposes `stories15M`, stop them. It is the seductive middle option: 15.2 M params, 60,816,028 bytes = **58.0 MiB of the 64 MiB SDRAM (90.6%)**, leaving no room for code, stack, or its 3.5 MB KV cache — and a 58 MB JTAG load is **8–17 minutes per edit-compile-test iteration**. Do not say "it doesn't fit"; say "it fits with nothing left over", which is both true and checkable.

---

## What we say on stage

Write it down verbatim and do not improvise:

> **"Karpathy's llama2.c — unmodified in its math — running bare metal on a Nios II
> soft core we programmed onto a MAX 10 FPGA. No ARM, no operating system, no
> filesystem. The processor didn't exist until we configured it into the fabric this
> afternoon."**

Precision matters here, and it is the difference between a good answer and a bad one
in Q&A:

- ✅ We **programmed** a soft core into fabric. It is genuinely soft — it exists only
  because we configured it.
- ❌ We did **not design** the CPU. The Nios II/f and its SDRAM controller are
  Intel's, prebuilt. Say so. It costs nothing and buys total credibility.
- ❌ Never say "we ran an LLM on an FPGA." We ran a **292K-parameter transformer** on
  a soft core. That is the interesting true thing.

## The honesty slide

Genuinely the best slide in the deck:

- The 10M50's 144 embedded 18×18 multipliers (288 in 9×9 int8 mode) could retire
  **~28.8 G int8 MAC/s at 100 MHz**
- The single 16-bit SDRAM caps what you can actually stream into them
- We used **almost none** of that — the Nios II does the math serially
- 205 KB of on-chip RAM cannot hold a 1 MB model, so it lives in the 64 MB SDRAM

**Now with the measured number, which makes the slide much stronger:** we retire
about **334 K MAC/s**. The fabric could do ~28.8 G. We are using roughly
**1/86,000th of the silicon in front of us**.

And we know exactly why, which is the part worth saying out loud: the prebuilt
core has **no data cache**, so every weight is fetched individually from a 16-bit
SDRAM — 357 ns per 4-byte read, measured. The bottleneck is not arithmetic, it is
feeding the arithmetic. That is the same wall a real accelerator hits, and it is
why "add more multipliers" would not have saved us.

Showing the gap between what the silicon *could* do and what we *did* is a stronger
move than pretending there is no gap.

## Acceptance criteria

- [ ] Reachable at a public https URL from a phone on **cellular**
- [ ] A token appears live, from the board
- [ ] Seconds-per-token displayed, **measured not estimated**
- [ ] "Built at Sundai" and both members credited on the page
- [ ] Repo public with a license
- [ ] Nobody claims a "real LLM on an FPGA"

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| **No `nios2-elf-gcc`** — Quartus ≥ 24.1, or the WSL1 rabbit hole on 19.1–23.1 | **high** | Install 18.1 Lite. Decide by 12:30. This is the #1 schedule risk. |
| Linker regions default to on-chip RAM | high | J5. Failure mode is a **silent hang** — check it first when nothing prints |
| `-mcustom-fpu-cfg=60-2` errors | medium | Drop the flag. Soft float still works, ~10–20× slower. Performance risk, not viability |
| Quoting an unmeasured tok/s on stage | medium | J7. Say "roughly a second per token, here it is" until measured |
| Venue wifi blocks the POST | low | Outbound HTTPS only, no inbound port. Falls back to replay mode |
| **Theme fit** — no sensor, no physical action | **high** | ADXL345 on board; ~30 lines of C to let motion steer generation. Only after 17:00 |

## Definition of done

A stranger opens a URL on their phone, sees words appearing one at a time, and is
told those words are being computed by a processor that did not exist this morning.
