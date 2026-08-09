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

A **Terasic DE10-Nano**. It is unusual because it has *two* computers on one board:

- **An ARM processor** that boots real Linux. You SSH into it. It runs programs.
  Think Raspberry Pi.
- **An FPGA** sitting right next to it, sharing the same memory.

They can talk to each other. That combination is the entire project: Linux runs
the AI model, and when the model needs heavy math done, it hands that math to the
FPGA next door.

Two other boards are also called "DE10." If it says **DE10-Lite** on the
silkscreen, it has no ARM, no Linux, and this plan does not work. Check first.

---

## 4. Why can't we just run ChatGPT on it?

Size. Real models are tens of gigabytes. This board has **1 gigabyte** of RAM,
total, shared between both chips.

So we run a **tiny** language model: 15 million parameters, trained on simple
children's stories. It writes things like *"Once upon a time there was a little
dog who liked to run."* It is genuinely a transformer, the same architecture as
the big ones, just small enough to fit.

Nobody is impressed by what it *says*. They are impressed by **where it runs**
and **how much faster we made it**.

If anyone on stage claims we are running a real LLM on an FPGA, we get taken
apart in Q&A. We are not. We are being precise about a small true thing, which
is a better demo than a big false one.

---

## 5. What is the actual trick?

Here is the whole insight.

We use a program called **llama2.c**. It is one C file, about 700 lines, that
runs a transformer. No libraries, no dependencies.

Inside it there is a single function:

```c
void matmul(float* xout, float* x, float* w, int n, int d)
```

**Roughly all of the work happens inside that one function.** Multiply, add,
multiply, add, millions of times. Everything else in the file is bookkeeping.

So we do not "port an AI model to hardware." We do this:

> Find the one slow function. Build a little circuit that does *only that
> function*, very fast, in parallel. Replace the function body with "hey FPGA,
> do this." Measure the difference.

That is it. That is the project. It is small enough to finish in a day
*specifically because* it is one function.

---

## 6. What is a "MAC" and why does it matter?

**MAC = Multiply-ACcumulate.** Multiply two numbers, add the result to a running
total. Repeat.

```
total = 0
total += a1 * b1
total += a2 * b2
total += a3 * b3   ...and so on, forever
```

That is what `matmul` does. That is what neural networks *are*, underneath.

A CPU does these mostly **one at a time**. An FPGA can lay down 32 or 64
multipliers side by side and do them **all in the same instant**, because they
are separate physical circuits and nothing forces them to take turns.

The DE10-Nano has about **112 dedicated multiplier blocks** in its fabric. That
is our budget.

---

## 7. Why int8 and not regular numbers?

Regular decimal numbers (`float`) need big, complicated circuits. Whole numbers
from -128 to 127 (`int8`) need small, simple ones, and the chip has dedicated
hardware for exactly that.

So we use llama2.c's quantized version (`runq.c`), which squashes the model down
to int8. Two benefits, free: it is already ~3x faster on the CPU and 4x smaller,
**and** it maps onto FPGA multipliers cleanly.

Slight loss of accuracy. For a model writing children's stories, nobody can tell.

---

## 8. How do the two chips talk?

The ARM side runs Linux. The FPGA side is just circuits. They meet through a
**bridge**, which works like a shared mailbox at a fixed address.

On this board the mailbox lives at address `0xFF200000`. A Linux program opens a
special file called `/dev/mem`, points at that address, and writing there is
physically the same as poking wires on the FPGA.

So the handoff is: **write numbers to the mailbox, FPGA does the math, read the
answer back out.**

---

## 9. What are we actually measuring?

One number, before and after:

```
tokens per second
```

A token is roughly a word. Run the model on the ARM alone: write the number
down. Turn on the FPGA accelerator: write the number down.

**Those two numbers side by side are the entire presentation.** Everything else
is supporting material.

---

## 10. Where does the "LLM writes Verilog" part come in?

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

## 11. What is a "testbench"?

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

## 12. Simulation vs synthesis (the thing that will eat our day)

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

## 13. What does "ship it" mean here?

Sundai's rule: *get off localhost. Deploy something on the actual internet.*

The board sits on the venue's local network, which nobody outside the room can
reach. So we run a tiny web server on the board and open a **Cloudflare tunnel**,
which hands us a public URL that forwards to it.

Anyone, anywhere, opens that link and sees the two tok/s numbers and live text
streaming out of an FPGA dev board sitting on a table in Boston.

---

## 14. Who does what

| Person | Owns |
|---|---|
| **Justin** | The Verilog and Quartus. He is the FPGA person; the fabric is his. |
| **Wilson** | The benchmark harness, the deployment, and the story. The things Justin will not have hands for while he is inside Quartus. |

Do not try to do Justin's half. Two people fighting over one synthesis queue is
slower than one person owning it.

---

## 15. If it all falls apart

The fallback is real, not decorative. Even with zero FPGA acceleration working,
we still walk on stage with:

- a working transformer running on an FPGA dev board's ARM core
- a measured benchmark of how well current LLMs write Verilog
- a deployed public page showing both

That is a fine result. Say the accelerator did not land, show the data you do
have, and do not pretend otherwise. Judges respect a clean negative far more than
a vague claim.
