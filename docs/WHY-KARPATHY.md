# Why we're using Karpathy's tiny LLM and not the two tiny-gpu repos

**ELI5 version. Read this before anyone starts building.**

Eugene (a Sundai speaker) suggested two repos. Justin passed them along. They are
good repos. They are also **not able to do the thing we want**, and the reason is
concrete and checkable, not a matter of taste.

Here is the whole argument in one table.

| | what it actually is | can it run a language model? |
|---|---|---|
| [`adam-maj/tiny-gpu`](https://github.com/adam-maj/tiny-gpu) | a real GPU written in **Verilog** | **No** |
| [`deaneeth/tiny-gpu`](https://github.com/deaneeth/tiny-gpu) | a GPU **simulator written in Python** | **No** |
| [`karpathy/llama2.c`](https://github.com/karpathy/llama2.c) | a language model in **one C file** | **Yes** |

---

## First, a name mix-up worth clearing up

These are **not** Karpathy's repos. Andrej Karpathy's tiny projects are llama2.c,
nanoGPT, and micrograd — all of them *software*. `tiny-gpu` is by Adam Majmudar,
and the second one is by someone else again. Same vibe in the naming, completely
different projects.

So the question "is Eugene talking about Karpathy's?" has a clean answer: **no.**

---

## Why `adam-maj/tiny-gpu` can't run our model

It's a genuinely nice piece of work, and it is *very close* to Justin's original
pitch. Two hard facts stop it being our path today.

### 1. Its memory holds 256 bytes

Not 256 megabytes. Not 256 kilobytes. **256 rows of 8-bit values.**

Our model is **1,056,540 bytes**.

```
tiny-gpu data memory     256 bytes
stories260K weights  1,056,540 bytes
                     ─────────────────
                     about 4,000x too big
```

You cannot put a 1 MB model into 256 bytes. There is no clever trick; it's a
wall.

### 2. It has never actually run on a chip

It is tested in **simulation** — software pretending to be hardware — using
`iverilog` and `cocotb`. Its memory isn't a real memory controller, it's a
behavioural stand-in that only exists inside the simulator.

The README lists FPGA support as a *future hope* ("an adapter for Tiny Tapeout
7"), not a feature. There are no synthesis results, no resource numbers, no
timing data. Nobody has put it on silicon.

### 3. And there's no compiler for it

It has its own custom 11-instruction language. There is no C compiler that targets
it. llama2.c is written in C. So even if the memory were big enough, there would
be no way to translate our model's code into something tiny-gpu understands.

---

## Why `deaneeth/tiny-gpu` is even further away

It isn't hardware at all. It's a **Python program** that pretends to be a GPU so
students can watch how one works, and it exports GIFs for classroom use. It isn't
a fork of the other repo and it contains no Verilog whatsoever.

You cannot put a Python program onto an FPGA. Different universe.

---

## Why Karpathy's model *does* work here

`stories260K` is the smallest checkpoint from llama2.c. Every number below has
been checked against the real files, not estimated:

| | |
|---|---|
| parameters | 292,000 |
| weights on disk | **1,056,540 bytes** (1.03 MB) |
| board memory available | **64 MB** |
| total footprint incl. working space | **2.6%** of the board |
| math per word | **259,328 multiply-adds** |
| speed on the core we're building | **0.1 – 3 seconds per word** |

And it writes actual sentences:

> *Once upon a time, there was a little girl named Lily. She loved to play outside
> in the sun.*

The reason it fits where a GPU design doesn't is that **llama2.c is one C file
with no dependencies.** No operating system needed, no libraries, nothing to
install. That's exactly the situation on a bare FPGA, where there is no operating
system to give you anything.

> We also checked the bigger model, `stories15M`. It's dead: **97 MB in full
> precision against 64 MB of memory on the board.** It doesn't fit. Most of its
> size is a 32,000-word vocabulary table; ours has 512 words.

---

## But we still need hardware to run it on

Here's the part that surprises people.

The board has **no processor.** None. It's a blank sheet of reconfigurable
circuitry.

So we build one. We describe a small RISC-V processor in code, load it onto the
FPGA, and now the chip *is* a computer. Then we compile the language model for the
computer we just made.

> **The stage line:** we synthesized a processor into the fabric and ran a language
> model on it. No ARM chip, no operating system. Every gate between the power plug
> and the text is something we put there.

---

## Where tiny-gpu still earns its place

None of the above means "ignore Eugene's tip." `adam-maj/tiny-gpu` is a **real
alternative project**, and it's arguably closer to Justin's original pitch:

> Take an educational GPU that has only ever existed in simulation, and make it run
> on actual silicon.

That's bounded, honest, and genuinely interesting. The work is writing the
synthesizable memory controller it's missing — which is *exactly* the kind of
module we're already benchmarking LLMs at writing. Its 2×2 matrix-multiply demo
would look great on the board's 7-segment displays.

So it's a fork in the road, not a merge:

- **Path A — a language model on a processor we built.** Better fit for an AI
  hackathon; the model is the point.
- **Path B — put tiny-gpu on real hardware.** Better fit for Justin's pitch and
  Eugene's suggestion; the hardware is the point.

**We are taking Path A**, because the hack's theme is foundation models and because
Path A's outcome ("it wrote a story") is legible to a non-hardware audience in one
second. Path B stays on the table as the fallback if the processor fights us — see
[`board/README.md`](../board/README.md) for the kill criteria.

Doing both today is not realistic, and pretending otherwise is how teams ship
nothing.
