# ELI5: what we are actually building

No jargon. If you already know a section, skip it.

---

## 1. What is an FPGA?

A normal chip (like the one in your laptop) has its circuits permanently etched
at the factory. It is what it is forever.

An **FPGA** is a chip full of blank logic blocks and wires that you rearrange
after you buy it. You describe a circuit in a text file, press a button, and the
chip physically rewires itself to become that circuit.

So instead of *writing software that runs on a processor*, you are **describing
a processor** (or any circuit) and the FPGA becomes it.

The tradeoff: rewiring is slow. Compiling that description into an actual wiring
map takes **15 to 30 minutes** every single time. Compare that to a C compiler
that takes half a second. This is the single most important fact about our day.

---

## 2. What is Verilog?

The language you describe circuits in. It looks a bit like C but it is not
programming, it is *drawing*. When you write

```verilog
assign y = a + b;
```

you are not saying "compute a plus b." You are saying "**physically place an
adder here**, wire `a` and `b` into it, and call the output `y`." That adder
exists permanently and computes continuously, whether you look at it or not.

This is why LLMs are bad at Verilog. They have read millions of lines of Python,
where code is a sequence of steps. Verilog is a description of a thing that
exists all at once. Models trained mostly on sequential code write Verilog that
looks right and describes a circuit that cannot be built.

**That is our benchmark:** how often, and in what specific ways, do they get it
wrong?

---

## 3. What board did Justin bring?

A **Terasic DE10-Lite**. We identified it from photographs — the silkscreen says
`DE10-Lite` and the chip itself is marked `10M50DAF484C7G`.

> **This corrects an earlier version of this document**, which assumed a
> DE10-*Nano*. That is a different board with an ARM processor that boots Linux.
> Justin's board has no such thing.

The DE10-Lite is a **pure FPGA**. It has:

- 50,000 logic elements (raw reconfigurable circuitry)
- 144 dedicated multiplier blocks
- 205 KB of memory inside the chip
- 64 MB of SDRAM sitting beside it
- 10 switches, 10 LEDs, six 7-segment displays, VGA, and a 40-pin connector

And, critically, it does **not** have:

- ❌ a processor of any kind
- ❌ an operating system
- ❌ ethernet
- ❌ an SD card slot, or any filesystem at all

So there is nothing to log into. There is no `ssh`. There is no place to copy a
file *to*. The board is a blank sheet of silicon.

---

## 4. Wait — if there is no processor, what runs the program?

**We build one.**

This is the part worth understanding, because it is the whole project.

An FPGA is reconfigurable circuitry. A CPU is just a particular arrangement of
circuitry. So you can *describe a processor in Verilog* and load that description
onto the FPGA, and now the chip **is** a processor. People do this constantly; it
is called a **soft core**. There are free, open-source ones you can drop in.

So the plan is:

1. Place a small RISC-V processor into the fabric.
2. Wire it to the 64 MB of SDRAM.
3. Compile a language model to run on it.
4. It writes a story.

This is *better* than what the DE10-Nano plan would have been. On a Nano, a real
ARM chip does the work and the FPGA helps with the math — the computer was already
there and we just rented a corner. Here there is no computer until we make one.

> **The one-sentence version for the stage:** we synthesized a processor into the
> fabric and ran a language model on it. No ARM, no operating system. Every gate
> between the power plug and the text is something we put there.

---

## 5. Why can't we just run ChatGPT on it?

Size, and it is not close. Real models are tens of gigabytes. This board has
64 megabytes.

So we run a **tiny** language model: `stories260K`, 292 thousand parameters,
trained on simple children's stories. Here is genuine output from it:

> *Once upon a time, there was a little girl named Lily. She loved to play outside
> in the sun.*

It is a real transformer — same architecture as the big ones — just small enough
to fit. It uses **2.6% of the board's memory**, including all its working space.

We originally planned to use `stories15M`, which is 50× bigger. That one is dead,
and not because it is slow: in full precision it is **97 MB, and the board only
has 64 MB**. It literally does not fit. (Most of its size is the vocabulary table:
32,000 words versus 512.)

Nobody is impressed by what the model *says*. They are impressed by **where it
runs**.

If anyone on stage claims we are running a real LLM on an FPGA, we get taken apart
in Q&A. We are not. We are being precise about a small true thing, which is a
better demo than a big false one.

---

## 6. What is the actual trick?

We use a program called **llama2.c** — one C file, about 700 lines, that runs a
transformer with no libraries and no dependencies. That "no dependencies" part is
why it is the right choice: our homemade processor has no operating system to
provide any.

Inside it there is a single function:

```c
void matmul(float* xout, float* x, float* w, int n, int d)
```

**Roughly all of the work happens inside that one function.** Multiply, add,
multiply, add, a quarter of a million times per word. Everything else is
bookkeeping.

So once the model is running on our soft processor, the upgrade is:

> Find the one slow function. Build a circuit that does *only that function*, many
> multiplications at once. Point the function at the circuit. Measure the
> difference.

Small enough to finish in a day *specifically because* it is one function.

---

## 7. How does the model get onto a board with no filesystem?

Normally a program opens the model file from disk. There is no disk. There is not
even a concept of a file.

So we turn the model **into source code**. A script reads the 1,056,540 bytes of
weights and writes them out as a giant C array:

```c
const unsigned char model260k[] = { 0x00, 0x00, 0x80, 0x3f, ... };
```

That gets compiled into the program itself and lives in SDRAM alongside it. Same
for the tokenizer. The model is not *loaded* — it is *part of the executable*.

---

## 8. What is a "MAC" and why does it matter?

**MAC = Multiply-ACcumulate.** Multiply two numbers, add the result to a running
total. Repeat.

```
total = 0
total += a1 * b1
total += a2 * b2
total += a3 * b3   ...and so on
```

That is what `matmul` does. That is what neural networks *are*, underneath.

A processor does these mostly **one at a time**. An FPGA can lay down dozens of
multipliers side by side and run them **all in the same instant**, because they
are separate physical circuits and nothing makes them take turns.

This board has **144 dedicated multiplier blocks**. That is our budget.

Our model needs about **260,000 MACs per word**. Even a slow homemade processor
retiring a million instructions a second gets us roughly a word per second, and a
decent one gets 10+ words per second. That is watchable.

## 9. Why int8 and not regular numbers?

Regular decimal numbers (`float`) need big, complicated circuits. Whole numbers
from -128 to 127 (`int8`) need small, simple ones, and the chip has dedicated
hardware for exactly that.

So we may use llama2.c's quantized version (`runq.c`), which squashes the model
down to int8. It maps onto the FPGA's multipliers cleanly and shrinks the model
from 1.03 MB to 0.29 MB.

There is a real open question here: our homemade processor has **no floating-point
unit**, so ordinary decimal math has to be emulated in software, which is slow.
Using int8 weights removes most of that problem. If it is still too slow, the next
step is converting the whole thing to fixed-point integers.

Slight loss of accuracy. For a model writing children's stories, nobody can tell.

---

## 10. How do we get the words off the board?

There is no ethernet and no serial port. The only wire to the outside world is the
same USB cable used to program the chip, which carries something called **JTAG**.

Our soft processor prints to a "JTAG UART" — a tiny virtual terminal that appears
on Justin's laptop. So the words come out there.

But Sundai requires a demo **on the public internet**, not on a laptop. So:

```
board ──JTAG──► Justin's laptop ──LAN──► Wilson's Mac ──tunnel──► public URL
```

Justin's machine reads the tokens and forwards them; Wilson's Mac serves the page
through a Cloudflare tunnel. No extra hardware needed.

(Why the split: **Quartus, the FPGA software, does not run on macOS at all.** So
Justin's machine is the only one that can talk to the board, and Wilson's is the
one that ships the website.)

## 11. What are we actually measuring?

One number, before and after:

```
tokens per second
```

A token is roughly a word. Run the model on the ARM alone: write the number
down. Turn on the FPGA accelerator: write the number down.

**Those two numbers side by side are the entire presentation.** Everything else
is supporting material.

---

## 12. Where does the "LLM writes Verilog" part come in?

Justin's original pitch was "measure how bad LLMs are at writing Verilog." We
get that for free.

Every circuit module we need, we ask Claude (and other models) to write. Then we
automatically record:

1. Is it valid Verilog at all? (does it lint)
2. Does it simulate?
3. Does it produce **correct answers** on a test we wrote ourselves?
4. Does it fit on the chip?

Ask each model the same question several times, log every attempt, and you have
a real dataset. It accumulates all day as a byproduct of doing the actual work.
No extra effort.

Point 3 matters most. Code that compiles but computes the wrong answer is the
interesting failure, and it is the one that only a testbench catches.

---

## 13. What is a "testbench"?

A second Verilog file that is **not** part of the circuit. It is a rig that:

- feeds known inputs into the circuit under test
- checks the outputs against answers we already know
- prints `ALL TESTS PASSED` or lists what broke

We write these **by hand**, deliberately. If the LLM wrote both the circuit and
its own test, a model that misunderstands the spec would write a test that agrees
with its own misunderstanding, and we would learn nothing. The test has to come
from outside.

This is the same reason you do not let a student grade their own exam.

---

## 14. Simulation vs synthesis (the thing that will eat our day)

Two very different steps, constantly confused:

| | Simulation | Synthesis |
|---|---|---|
| What it does | Pretends to be the circuit, in software | Actually builds the wiring map |
| Tool | `iverilog` / `verilator` | Quartus |
| Time | **~1 second** | **15 to 30 minutes** |
| Catches | Wrong math, wrong logic | Physically impossible circuits |

**Rule for the day: nothing gets synthesized until it passes simulation.**

You get maybe 12 to 15 synthesis runs in a working day. Spending one on a module
that had an obvious bug is throwing away 30 minutes you do not have. Simulation
is free, so simulate everything, always, first.

---

## 15. What does "ship it" mean here?

Sundai's rule: *get off localhost. Deploy something on the actual internet.*

The board sits on the venue's local network, which nobody outside the room can
reach. So we run a tiny web server on the board and open a **Cloudflare tunnel**,
which hands us a public URL that forwards to it.

Anyone, anywhere, opens that link and sees the two tok/s numbers and live text
streaming out of an FPGA dev board sitting on a table in Boston.

---

## 16. What about tiny-gpu? (Eugene's suggestion)

Eugene pointed at two repos. They are not what the names suggest, so read this
before anyone spends the afternoon on them.

**They are not Karpathy's.** Karpathy's tiny projects (llama2.c, nanoGPT,
micrograd) are all *software*. These are different people and different things.

| repo | what it actually is | runs on an FPGA? |
|---|---|---|
| `adam-maj/tiny-gpu` | a real GPU written in **Verilog** — ISA, cores, memory controllers | **no — simulation only** |
| `deaneeth/tiny-gpu` | a GPU **simulator written in Python**, not a fork of the above | no — it is not hardware at all |

`adam-maj/tiny-gpu` is genuinely good and genuinely relevant — it is almost exactly
Justin's original "vibe-coded GPU" pitch. But two facts decide how we can use it:

1. **It has never been synthesized.** It is tested with `iverilog` and `cocotb`
   against a *behavioural* memory model — there is no real memory controller. The
   README lists FPGA support as a future aspiration ("adapter for Tiny Tapeout 7"),
   not a feature. No resource, timing, or utilization numbers exist.
2. **Its memory is 256 rows of 8-bit values.** That is 256 *bytes*. Our model is
   1,056,540 bytes. It is roughly 4,000× too small to hold the model, and its
   11-instruction custom ISA has no C compiler, so llama2.c could not be compiled
   for it anyway.

So tiny-gpu **cannot run a language model**. Anyone who says otherwise has not read
the memory map.

What it *can* be is a strong project in its own right: **take an educational GPU
that has only ever existed in simulation and make it run on real silicon.** That is
Justin's pitch exactly, it is bounded, and its 2×2 matrix-multiply kernel displays
beautifully on the 7-segments. The work is writing the synthesizable memory
controller it lacks — which is precisely the kind of module we are already
benchmarking LLMs on.

That is a fork in the road, not a merge:

- **Path A — language model on a CPU we built.** Fits an AI hackathon's theme.
- **Path B — put tiny-gpu on real hardware.** Fits Justin's pitch and Eugene's tip.

Both are honest. Doing both today is not.

---

## 17. Who does what

| Person | Owns |
|---|---|
| **Justin** | The Verilog and Quartus. He is the FPGA person; the fabric is his. |
| **Wilson** | The benchmark harness, the deployment, and the story. The things Justin will not have hands for while he is inside Quartus. |

Do not try to do Justin's half. Two people fighting over one synthesis queue is
slower than one person owning it.

---

## 18. If it all falls apart

The fallback is real, not decorative. Even with zero FPGA acceleration working,
we still walk on stage with:

- a working transformer running on an FPGA dev board's ARM core
- a measured benchmark of how well current LLMs write Verilog
- a deployed public page showing both

That is a fine result. Say the accelerator did not land, show the data you do
have, and do not pretend otherwise. Judges respect a clean negative far more than
a vague claim.
