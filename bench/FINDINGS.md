# Findings — and why the headline number should not be quoted

**Question:** given the same specification, are LLMs worse at VHDL than Verilog?

**Answer: this apparatus cannot tell you.** Below is what it produced, why the
number is not trustworthy, and the one result that is.

Reported this way deliberately. The clean-looking version of this page would say
"96.3% vs 96.3%, no significant difference" and it would be wrong in a way nobody
would catch until someone asked a good question.

---

## The result, stated with its caveats attached

54 attempts: 3 models × 3 tasks × 2 languages × 3 trials.

| | including refusals | excluding refusals |
|---|---|---|
| Verilog | 26/27 — 96.3% | **26/26 — 100.0%** |
| VHDL | 26/27 — 96.3% | **26/26 — 100.0%** |

Every single non-refused attempt passed, in both languages, across Opus 5,
Sonnet 5 and Haiku 4.5.

**The tasks are too easy to discriminate.** You cannot measure a gap with an
instrument that reads full marks everywhere. That alone ends the headline claim,
before any of the defects below.

---

## Three ways the apparatus is broken

All of these were found by adversarial review that **ran code**, not by reading it.

### 1. BLOCKER — the languages are not graded to the same standard

Demonstrated:

| deviation from spec | Verilog | VHDL |
|---|---|---|
| all ports declared unsigned, arithmetic fixed with `$signed` casts | **passes** | dies at elaborate |
| `acc` port 16 bits wide where the spec says 32 | **passes** | dies at elaborate |

`iverilog` silently pads and coerces port connections. GHDL enforces them. Both
system prompts issue the identical demand that port names, directions and widths
match exactly — only one toolchain checks.

So VHDL attempts land in the `elab` bucket for mistakes Verilog is forgiven, and
the bias runs **in exactly the direction the benchmark set out to measure**. Any
non-zero delta this apparatus produced would be suspect for this reason alone.

### 2. MAJOR — the specs leak the answer

`mac_array8/spec.md` and its VHDL sibling both end with:

> *"The eight multiplies must be signed; unpacking the bytes as unsigned is the
> failure mode to avoid."*

That names the defect under test, violating rule 4 of `CONTRACT.md` and
contradicting this repo's own README. The leak is symmetric, so it does not bias
the *delta* — but it inflates **both** columns and is a large part of why
everything scored full marks.

### 3. MAJOR — the testbenches have blind spots

`results/testbench-validation.txt` records 12/12 discrimination, and that result
stands — but it only proves the testbenches catch **the three defects we
planted**. A reviewer wrote new ones and found real gaps, verified by execution:

| undetected defect | why it slips through |
|---|---|
| 16-bit internal accumulator, sign-extended to the 32-bit port | stimulus never accumulates past 16,106 — well inside 16-bit range |
| big-endian byte unpacking in `mac_array8` | every vector pairs a varying `a` against a **constant** `b`, so any permutation sums identically |
| asynchronous reset where the spec says synchronous | `rst` only ever changes while the clock is idle, so the async path is never observed |

All three pass in **both** languages. The spec's "accumulation is in 32-bit
signed arithmetic and is allowed to wrap" is entirely untested.

**Lesson:** validating a testbench against defects you chose yourself proves it
catches those defects. It does not prove the testbench is good. Someone else has
to try to break it.

### 4. MAJOR — the VHDL extractor truncates naturally-shaped answers

`extract_vhdl` takes only the **first** fenced code block. VHDL prose commonly
splits entity and architecture across two fences. The resulting entity-only file
**passes the lint gate** (`ghdl -a` accepts an entity with no architecture) and
dies at elaborate.

Verilog has no equivalent failure mode — a module is one contiguous block, so a
truncated one fails at lint instead. This penalizes the VHDL column for a parser
limitation rather than model competence.

---

## The finding that IS solid

Reproducible, isolated, and measured today:

> **`"You write synthesizable Verilog-2001 for FPGA targets."` causes
> `claude-opus-5` to return `stop_reason="refusal"`** — empty content, 3 output
> tokens — in response to a benign signed-MAC specification.

Bisected line by line. Every other line of the system prompt is fine. The
sentence alone reproduces it.

The trigger is startlingly brittle:

| system prompt opening | result |
|---|---|
| `You write synthesizable Verilog-2001 for FPGA targets.` | ❌ refusal |
| `You write synthesizable Verilog-2001 for FPGA targets` *(no period)* | ✅ ok |
| `You write synthesizable Verilog for FPGA targets.` *(no "-2001")* | ✅ ok |
| `You produce synthesizable Verilog-2001 modules for FPGA targets.` | ❌ refusal |
| `You are an expert digital design engineer writing synthesizable Verilog-2001 for FPGA targets.` | ❌ refusal |
| `Respond with synthesizable Verilog-2001 suitable for an FPGA target.` | ✅ ok |

Sonnet 5 and Haiku 4.5 are unaffected. Removing the system prompt entirely makes
Opus produce 3,592 characters of correct VHDL for the same spec.

### Why this matters more than the pass rate

**The first run of this benchmark reported that VHDL was 14.8 points worse.**

That number was entirely this artifact. 15 of 54 attempts were refusals, split
lopsidedly across languages, sitting inside the pass-rate denominator. Had it
been quoted, an API refusal classifier would have been presented as a property of
a programming language.

It was caught because the pattern was implausible — the *strongest* model failing
where weaker ones succeeded — and that implausibility was worth chasing rather
than reporting.

`harness.py` now counts refusals separately and prints a warning when they are
lopsided across languages. The system prompt carries a comment explaining exactly
why its opening sentence must not be "improved".

---

## What would make this benchmark real

In rough order of importance:

1. **Equalize the gates.** Add a port-signature check to the Verilog path, or
   make the Verilog testbench binding type-strict, so both languages reject the
   same deviations.
2. **Harder tasks.** Everything passes at 100%; there is no signal. Needs
   designs where competent models actually fail — state machines, CDC, pipelined
   arithmetic with backpressure.
3. **Strip the spec leak** from `mac_array8` and re-run.
4. **Fix `extract_vhdl`** to concatenate all fenced blocks, and require both an
   entity and an architecture before scoring.
5. **Fix the testbench blind spots** — accumulate past 32,767, vary both operands
   asymmetrically, and toggle reset while the clock runs.
6. **Add a synthesis gate.** Simulatable ≠ synthesizable. That needs Quartus, so
   it needs the Windows machine.

## What can honestly be said out loud

- We built a matched dual-language HDL benchmark with validated testbenches.
- It found **no measurable difference** between Verilog and VHDL on these tasks,
  because the tasks are too easy — every non-refused attempt passed.
- Along the way it produced a **wrong** answer (−14.8 points) that was purely an
  API refusal artifact, and we caught it.
- We found and isolated a reproducible prompt-sensitivity bug in Opus 5.

What must **not** be said: that VHDL is worse, or that it is the same. This
apparatus is not yet capable of supporting either claim.
