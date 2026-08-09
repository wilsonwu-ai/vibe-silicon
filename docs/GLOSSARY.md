# Glossary — every term and acronym in this repo

Written so that someone who has never touched hardware can read the rest of the
repo. Each entry says what it is, and where relevant, **why it matters here**.

If you only read three entries, read **FPGA**, **HDL**, and **simulation vs
synthesis**. Everything else hangs off those.

---

## The big three

### FPGA — Field-Programmable Gate Array

**A chip you rewire after buying it.**

A normal chip — the processor in your laptop — has its circuitry fixed at the
factory. It can run different *software*, but it is always the same *hardware*.

An FPGA is a grid of blank logic that you configure into whatever circuit you
want. Want a video decoder? Configure one. Want it to be a music synthesizer
instead? Reconfigure it. The physical chip does not change; the wiring inside it
does.

"Field-programmable" means programmable after it leaves the factory — in the
field. "Gate array" is the grid of logic gates you are wiring together.

**Why it matters here:** our board's FPGA has no processor on it. So we put one
there. That is the entire project.

### HDL — Hardware Description Language

**A programming language for describing circuits instead of steps.**

This is the part that trips people up. Normal code is a *recipe*: do this, then
this, then this. HDL is a *blueprint*: these wires connect to this adder, whose
output feeds this register, and all of it exists **simultaneously and
permanently**.

There is no "then" in hardware. Everything happens at once, forever, until the
power goes off.

```verilog
assign sum = a + b;     // NOT "compute a+b once"
                        // it means "there is physically an adder here,
                        // and its output is always a+b"
```

That difference is exactly why LLMs are worse at HDL than at Python — and it is
what our benchmark measures.

The two main HDLs are **Verilog** and **VHDL**. They do the same job.

### Simulation vs synthesis

The single most useful distinction in this repo.

| | **simulation** | **synthesis** |
|---|---|---|
| what happens | software *pretends* to be the circuit and runs it | your design is compiled into actual gates for a real chip |
| tools | `iverilog`, `ghdl` — free, any OS | Quartus — Windows/Linux only |
| takes | about 1 second | about 25 minutes |
| needs a chip? | **no** | yes, to program afterwards |

**Why it matters here:** our benchmark is 100% simulation, which is why it runs
on a Mac while the board sits on a Windows machine — and why it still ships if
the board never works. Justin's side needs synthesis, which is why he needs
Quartus and Wilson cannot help with it.

---

## Languages and tools

| term | what it is |
|---|---|
| **Verilog** | The more C-like HDL. Dominant in the US and in open-source tooling. What our benchmark's tasks are written in. |
| **VHDL** | The more verbose, strongly-typed HDL. Common in Europe, aerospace, defense. LLMs are measurably worse at it — that gap is what we set out to measure. |
| **RTL** — Register Transfer Level | The style of HDL that describes circuits as registers plus the logic between them. When people say "writing RTL" they mean "writing synthesizable HDL". |
| **testbench** | A program that exercises your circuit in simulation, feeding it inputs and checking outputs. The model being benchmarked never sees ours. |
| **lint** | A first check that code is well-formed, before doing anything expensive with it. |
| **elaborate** | Resolving a design into a concrete hierarchy of connected parts, ready to simulate. Between lint and simulate. |
| **iverilog / vvp** | Icarus Verilog — free Verilog simulator. `iverilog` compiles, `vvp` runs. |
| **GHDL** | Free VHDL simulator. The VHDL equivalent of the above. |
| **Quartus** | Intel's FPGA design software. Does synthesis and programs the board. **Has never had a macOS build**, which is why one teammate does all the hardware work. |
| **WSL** — Windows Subsystem for Linux | Runs Linux inside Windows. Newer Quartus needs it for the Nios II tools — and specifically **WSL 1**, not 2. Avoiding that is why we pinned Quartus 18.1. |

---

## Our board

| term | what it is |
|---|---|
| **DE10-Lite** | The board Justin brought. Made by Terasic, aimed at universities. |
| **MAX 10** | The family of Intel FPGA chip on it. Notable for being a *pure* FPGA — no built-in processor. |
| **`10M50DAF484C7G`** | The exact part number, read off the chip in a photo. `10M50` = MAX 10, 50K logic elements. The rest is package and speed grade. |
| **LE** — Logic Element | The basic unit of FPGA capacity. Ours has ~50,000. Think of it as "how much circuit fits". |
| **M9K** | Blocks of memory inside the FPGA itself. Ours has ~205 KB total — **too small for our 1 MB model**, which is why the model lives in external SDRAM. |
| **18×18 multiplier / DSP block** | Dedicated multiplier circuits, faster and smaller than building one out of logic. Ours has 144. Multiplication is what neural networks are made of. |
| **SDRAM** | The board's external memory chip — 64 MB. Where our model and its working memory live. |
| **SoC** — System on Chip | One chip containing a processor *and* other things. The DE10-**Nano** is an SoC FPGA (has a real ARM processor). The DE10-**Lite** is not. Assuming otherwise cost us two hours. |
| **HPS** — Hard Processor System | The real, factory-built processor inside an SoC FPGA. Our board has none. |
| **ARM / Cortex-A9** | The processor family in phones and in the DE10-Nano. **Not present** on our board. |
| **USB-Blaster** | The circuit on the board that lets a PC program the FPGA over USB. |
| **JTAG** | An old, universal standard for talking to chips for debugging and programming. On our board it is the only wire to the outside world, so the model's output comes out over it. |
| **UART** | A simple serial text channel. A "JTAG UART" is a text terminal tunnelled over JTAG — how the board prints words to a laptop. |
| **GPIO** — General Purpose Input/Output | Pins you can wire to anything. |
| **7-segment display** | The figure-8 numeric displays. Our board has six. |
| **ADXL345** | The accelerometer chip on the board — it senses motion. Relevant because the hackathon's theme is foundation models for the *physical* world. |
| **bitstream / `.sof`** | The file that configures an FPGA — the "wiring diagram" you load onto it. `.sof` is Intel's format. |

---

## Processors we put *into* the FPGA

| term | what it is |
|---|---|
| **soft core** | A processor built out of FPGA logic rather than etched into silicon. It exists only because you configured it. **This is the heart of our project:** the board has no CPU until we make one. |
| **Nios II** | Intel's soft-core processor. **Removed from Quartus at version 24.1**, which is why Justin had to install 18.1. |
| **Nios II/f vs /e** | "Fast" and "economy". `/f` is pipelined and can have hardware floating point; `/e` is tiny and slow. |
| **RISC-V** | An open, royalty-free processor instruction set. Lots of free soft cores implement it. We considered NEORV32 before finding the prebuilt Nios II option. |
| **bare metal** | Running a program with **no operating system** underneath. No Linux, no files, no `malloc` unless you provide it. That is our situation. |
| **FPU** — Floating Point Unit | Hardware for decimal math. Without one, decimals are emulated in software — 10–20× slower. Whether ours has one is the difference between 0.1 and 3 seconds per word. |
| **BSP** — Board Support Package | The generated glue telling your program where memory and devices live on this specific board. |
| **linker regions** (`.text`, `.rodata`, `.data`, `.bss`, heap, stack) | Where the parts of a program live in memory: code, constants, initialized data, zeroed data, and scratch space. **Our biggest landmine** — if `.bss` is placed in the 64 KB on-chip RAM instead of the 64 MB SDRAM, our 1.8 MB program hangs with no error message. |
| **ELF** | The standard file format for a compiled program. |
| **objcopy** | A tool that turns any file into a linkable object — how we get the model weights *into* the executable when there is no filesystem to read them from. |
| **newlib** | A small C library for systems with no OS. Its floating-point `printf` is enormous, which is why our code never prints a `%f`. |

---

## The AI side

| term | what it is |
|---|---|
| **LLM** — Large Language Model | A model trained to predict the next piece of text. ChatGPT and Claude are LLMs. Ours is *very* small. |
| **transformer** | The architecture behind essentially all modern language models. Ours is a real one, just tiny. |
| **inference** | *Using* a trained model, as opposed to training it. We only do inference — the hackathon's brief explicitly says start from a pretrained model. |
| **parameters** | The learned numbers inside a model. GPT-4 has ~a trillion; ours has **292,000**. |
| **token** | Roughly a word, or a word-piece. Models read and write tokens, not letters. |
| **tokenizer** | The lookup table converting text to tokens and back. Ours knows 512 tokens; the bigger model's knows 32,000 — which is why *that* model is 58 MiB, filling 91% of the board's memory and leaving no room for anything else. |
| **KV cache** | Memory of what the model has already read, so it does not recompute it for every new word. Trades memory for speed. |
| **MAC** — Multiply-ACcumulate | Multiply two numbers, add to a running total, repeat. **This is what neural networks are, underneath.** Our model needs 259,328 of them per word. |
| **rmsnorm, softmax, RoPE, attention** | The mathematical steps inside a transformer. We did not modify any of them — that is the point of generating our port with a script instead of hand-editing. |
| **fp32 / int8** | 32-bit decimals vs 8-bit whole numbers. int8 is 4× smaller and maps neatly onto FPGA multipliers. |
| **quantization** | Squashing a model from fp32 to int8. Smaller and faster, slightly less accurate. For a model writing children's stories, nobody can tell. |
| **llama2.c** | Andrej Karpathy's implementation of a Llama-2 style model in **one C file with no dependencies**. That "no dependencies" property is exactly why it can run on a bare-metal soft core. |
| **stories260K / stories15M** | Karpathy's tiny models trained on simple children's stories. We use the 260K one. |

---

## The web side

| term | what it is |
|---|---|
| **Cloudflare Worker** | Code that runs on Cloudflare's servers worldwide. Hosts our public page. |
| **Durable Object** | A Worker with memory that persists and is shared between visitors — how everyone watching sees the same token stream. |
| **SSE** — Server-Sent Events | A one-way live feed from server to browser. How words appear on the page as they are generated. |
| **bearer token** | A secret string proving a request is allowed. Stops strangers posting text to our demo. |
| **`tar.gz` vs `.zip`** | Two archive formats. Unix prefers the first, Windows the second. We shipped the wrong one at first. |
| **Gatekeeper / quarantine** | macOS security that blocks unsigned downloads. It blocked GHDL **silently** — the command printed nothing at all. |

---

## Project shorthand

| term | what we mean by it |
|---|---|
| **gate** | A checkpoint with a deadline. Pass it or switch to the fallback. |
| **kill criteria** | Written-in-advance rules for abandoning something. Decided while calm, so they are not argued about at 18:00 while stressed. |
| **the honesty slide** | The deliberate slide showing what the hardware *could* do versus what we *actually* used. Showing the gap is stronger than pretending there isn't one. |
| **golden reference** | Known-correct output. Everything else is checked against it. |
| **byte-identical** | Output that matches the reference exactly, every character. What we verified for our port — a much stronger claim than "it looks right". |

---

## Why any of this matters

Every AI demo you have seen runs on hardware somebody else built — a GPU in a
data centre, a laptop, a phone.

We started with a chip that **contains no computer at all**, built one inside it,
and taught it to write a story. Then, separately, we measured how good AI models
actually are at writing the hardware descriptions such a machine is made of —
because that is the loop closing: models that can design the silicon that runs
models.

The small honest version of that is worth more than a large false one, which is
why this repo keeps stating exactly what it did and did not do.
