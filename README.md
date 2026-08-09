# vibe-silicon

**Can an LLM write the hardware that runs an LLM?**

Sundai Hack 135 — Foundation Models for the Physical World (Aug 9, 2026)

We run a small transformer on the ARM core of a Terasic DE10-Nano, then move its
inner loop (an int8 matrix-vector multiply) into the FPGA fabric and measure the
tokens/sec difference. Every Verilog module along the way is written by an LLM,
and we log whether each one lints, simulates, passes its testbench, and
synthesizes.

Two deliverables, one pipeline:

1. **A speedup number.** CPU-only tokens/sec vs FPGA-accelerated tokens/sec, on
   the same board, running the same model.
2. **A benchmark.** How good are current LLMs at writing synthesizable Verilog?
   Measured, not vibed.

The second one is insurance. If the HPS-to-FPGA bridge eats the afternoon, the
benchmark still ships.

---

## Why this is the right hardware for this demo

At 15M parameters on an 800MHz ARM Cortex-A9, inference is **compute bound**,
not memory-bandwidth bound. That is the one regime where a modest FPGA MAC array
actually wins. On a faster CPU with a bigger model you would be bandwidth bound
and the FPGA would buy nothing.

DE10-Nano specifics:

| | |
|---|---|
| SoC | Cyclone V `5CSEBA6` |
| CPU (HPS) | Dual-core ARM Cortex-A9 @ 800MHz, **ARMv7 (32-bit)** |
| RAM | 1GB DDR3, shared HPS/FPGA |
| Fabric | 110K logic elements, ~112 DSP blocks |
| Bridges | Lightweight HPS-to-FPGA @ `0xFF200000`, HPS-to-FPGA @ `0xC0000000` |

ARMv7 matters: nothing precompiled for `aarch64` runs here, and llama.cpp's good
ARM kernels target ARMv8. That is why we use llama2.c instead.

---

## The architecture, in one paragraph

[llama2.c](https://github.com/karpathy/llama2.c) is a single C file with no
dependencies. The overwhelming majority of inference cycles go through one
function, `matmul()`. We do not accelerate "an LLM" — we replace one function
body with a memory-mapped call into FPGA fabric. That scoping is what makes this
finishable in a day.

We use the quantized build (`runq.c`, Q8_0 int8) because int8 maps onto DSP
blocks cleanly and fp32 does not.

```
stories15M_q80.bin
       |
   runq.c on ARM  ──── matmul() ────►  [ CPU baseline: ~10-30 tok/s ]
       |                    |
       |                    └──────►  mmap /dev/mem @ 0xFF200000
       |                                      |
       |                              int8 MAC array in fabric
       |                                      |
       └──── web UI (cloudflared tunnel) ◄────┘
```

---

## Repo layout

```
board/      bring-up scripts for the DE10-Nano (Linux + llama2.c baseline)
bench/      LLM-writes-Verilog benchmark harness
  tasks/    one directory per task: spec.md + tb.v
  results/  results.jsonl (append-only)
rtl/        the accelerator itself (LLM-generated, human-reviewed)
web/        the demo page
docs/       ELI5.md — everything here in plain English
```

Start with [docs/ELI5.md](docs/ELI5.md) if any of the above is unfamiliar.

---

## Quickstart

**Benchmark (no board required, runs on your laptop):**

```bash
brew install icarus-verilog verilator
pip install anthropic
python3 bench/harness.py --trials 3
```

**Board bring-up:** see [board/README.md](board/README.md).

---

## Schedule (hack day)

| Time | Gate |
|---|---|
| 14:00 | Linux booted, `runq` running, baseline tok/s recorded. If not: drop the FPGA half, ship the benchmark. |
| 17:00 | Accelerator passing simulation. Harness logging. |
| 19:00 | Deployed. Freeze whatever state it is in. |
| 19:30 | Rehearse. |

Every synthesis run costs 15 to 30 minutes. That is roughly 12 to 15 runs left
in a day, total. Budget them like money: **every module simulates in iverilog
before it is allowed to consume a synthesis slot.**
