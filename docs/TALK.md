# The talk — 8pm, Sundai Hack 135

Two versions. Rehearse both out loud once before 19:30. Every number here was
measured today; nothing is derived.

---

## The 30-second version

> **This board has no processor.**
>
> It's a MAX 10 FPGA — blank reconfigurable logic. No ARM, no operating system,
> no filesystem, nothing to boot.
>
> So we put a processor in it. Then we compiled a language model for the
> processor we'd just made, and it wrote a story.
>
> **256 tokens. Byte-identical to the reference implementation. 1.02 seconds per
> token, measured.**
>
> *[point at the screen]* That's it running.

Stop there. Let them ask.

---

## The 3-minute version

### 1. The setup (30s)

> Everyone's AI demo today runs on hardware somebody else built — a GPU in a data
> centre, a laptop, a phone.
>
> We started with a chip that contains **no computer at all**.
>
> This is a Terasic DE10-Lite. The chip is an Intel MAX 10 — 50,000 logic
> elements, 144 multipliers, 64 megabytes of RAM. What it does *not* have is a
> processor. It's a blank sheet of circuitry.

### 2. What we did (45s)

> An FPGA is a chip you rewire after buying it. A CPU is just one particular
> arrangement of circuitry. So you can *describe a processor* and load that
> description onto the chip — and now the chip **is** a processor. It's called a
> soft core.
>
> We put a Nios II core into the fabric, wired it to the 64 MB of SDRAM, and
> compiled Karpathy's `llama2.c` to run on it, bare metal.
>
> There's no filesystem — no SD card, nothing to open a file from. So the model
> isn't *loaded*. It's **compiled into the executable** as a C array. A million
> bytes of weights, linked in like any other constant.

### 3. The honest scoping (30s)

> It's a **292,000-parameter** model. Not a large language model — a small one,
> and I want to be precise about that rather than let anyone assume otherwise.
>
> We're also not claiming to have designed the CPU. The Nios II core and its
> SDRAM controller are Intel's, prebuilt. What we wrote is the bare-metal port
> and the measurements.
>
> What *is* true: **every neural-network function is byte-for-byte upstream.**
> We generated the port with a script instead of hand-editing, precisely so we
> could say that and mean it. And the board's output is byte-identical to the
> reference — all 256 tokens, no float divergence.

### 4. The result and why it's the interesting part (45s)

> **1.02 seconds per token.**
>
> We predicted 0.1 to 0.2. So we went and found out why — and this is the part
> worth your attention.
>
> It is **not** the math. The floating-point unit is present and active; we
> confirmed 66 custom FP instructions in the binary.
>
> The core has **no data cache**. Zero bytes. So each of the ~259,000 weight
> reads per token is an individual, uncached transaction to a 16-bit memory.
>
> **The processor spends its life waiting, not multiplying.** It's a memory
> problem wearing a compute problem's clothes.

### 5. The close (30s)

> Which is exactly what Eugene told us this afternoon — *"the bytes go through
> the I/O."*
>
> His suggestion was ternary weights: constrain every weight to −1, 0 or +1, and
> multiplication stops existing. Plus-one is a wire. Minus-one is a sign flip.
> Zero is a switch left open. This chip has 144 multipliers and 50,000 logic
> elements, so that trade turns our scarcest resource into our most abundant one
> — and at 1.58 bits per weight instead of 32, it's a **20× cut in exactly the
> traffic we just proved is the bottleneck.**
>
> We didn't do it. You can't convert a model to ternary in an afternoon — it has
> to be trained that way. So it's in the repo, labelled as the thing we didn't
> do, credited to Eugene.
>
> **We measured the bottleneck. His idea targets it. That's tomorrow.**

---

## The numbers, if asked

| | |
|---|---|
| Board | Terasic DE10-Lite, Intel MAX 10 `10M50DAF484C7G` |
| Fabric | 50K logic elements · 144 multipliers · 205 KB on-chip RAM |
| Memory | 64 MB SDRAM, 16-bit |
| Core | Nios II/f soft core @ 100 MHz, FPU active, **0 B data cache** |
| Model | `stories260K` — 292K params, 1,056,540 bytes |
| Footprint | 1.7 MB of 64 MB = **2.6%** |
| Math | **259,328 MACs per token** |
| Result | **256/256 tokens, byte-identical, 1.020 s/token** |
| ELF | 1,984,108 B — text 1,201,836 · data 7,276 · bss 774,996 |
| JTAG load | 1,181 KB in 20.3 s (58.1 KB/s) |

`powf` measured at **317 µs — 100× a plain float multiply.** Upstream calls it
160×/token; the values depend only on `(pos, i)`, so ~50 ms/token is recoverable.
We left it alone. Byte-identical is worth more than 7%.

---

## Questions we should expect

**"Is this a real LLM?"**
> No, and I'd rather say so. 292,000 parameters, trained on children's stories.
> A real transformer architecturally — same attention, same RMSNorm, same RoPE —
> just small. What's interesting isn't what it says, it's where it runs.

**"Did you design the CPU?"**
> No. The Nios II core and SDRAM controller are Intel's prebuilt design. We
> programmed it into the fabric and wrote the bare-metal port. Building the SoC
> ourselves was the plan for about twenty minutes, until we found the prebuilt
> one — and dropping that was the best decision of the day.

**"Why so slow?"**
> No data cache. 259,000 uncached reads per token against 16-bit memory. The FPU
> is fine; the memory system is the wall.

**"Why not just use the 144 multipliers?"**
> That's the right question and the honest answer is we didn't get there. The
> Nios II does the math serially. Those multipliers could retire roughly 28.8
> billion int8 MACs a second at 100 MHz and we used almost none of it. The gap
> between what the silicon *could* do and what we *did* is real, and pretending
> otherwise would be worse than showing it.

**"What would you do with more time?"**
> Ternary weights, and it isn't my idea — Eugene suggested it this afternoon and
> then our own measurement confirmed his diagnosis.

**"What about the Verilog benchmark?"**
> We built it and it ran, and I won't quote the headline. It came out 96% versus
> 96%, but `iverilog` accepts port mismatches that GHDL rejects — the two
> languages weren't being graded to the same standard, so the comparison isn't
> sound yet. An earlier run said VHDL was 14.8 points worse and that turned out
> to be entirely an API artifact. It's written up honestly in the repo. The
> apparatus is real; the headline isn't yet.

---

## Do not say

- ❌ "We ran an LLM on an FPGA" → **a 292K-parameter transformer**
- ❌ "We built a CPU" → **we programmed a prebuilt soft core into the fabric**
- ❌ "VHDL is worse than Verilog" → **our benchmark can't support that yet**
- ❌ any tokens/sec number other than **1.02 s/token measured**

## Order of operations at the podium

1. Public page already open on the projector — **https://vibe-silicon.wilson-af8.workers.dev**
2. Board visible, powered, LEDs going
3. Start the run *before* you start talking — 20 s of JTAG load, then ~1 word/second
4. If anything dies: play the recording. It exists for this.
