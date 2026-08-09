# How bad are LLMs at writing hardware?

The question, precisely: **given the same specification, how much worse are LLMs
at VHDL than at Verilog?**

This is the second deliverable of vibe-silicon, and it is deliberately
independent of the FPGA. It runs entirely in simulation on any laptop, so it
ships whether or not the board ever works.

## Why an API key is required

To measure how well models write HDL, you have to ask models to write HDL —
repeatedly, across models, and grade each attempt. That is what the key pays for.

```
spec.md ──► Claude (raw API) ──► one module ──► lint ──► elaborate ──► simulate
```

**Why not run it through Claude Code?** Because Claude Code is an agent: it has
its own system prompt, tools, file access, and it can iterate on failures.
Benchmarking through it would measure *the agent*, not *the model*. A clean
result needs raw completions, a controlled prompt, and exactly one attempt per
trial. That distinction is the difference between a benchmark and a demo.

The key is read from `ANTHROPIC_API_KEY`. It is never committed — see
`.gitignore`.

**Cost:** 3 models × 3 tasks × 2 languages × 3 trials = 54 generations of a
small module. Low single-digit dollars.

## Simulation, not synthesis — and why that matters

| | simulation | synthesis |
|---|---|---|
| what | software models the circuit and runs it | compiles the design into real gates |
| tool | `iverilog`, `ghdl` — free, any OS | Quartus — Windows/Linux only |
| time | ~1 second | ~25 minutes |
| hardware | none | an FPGA, afterwards |

This benchmark is **entirely simulation**. That is why it runs on a Mac while
the board sits on a Windows machine, and why it is the insurance deliverable.

**The honest limitation:** it measures *"does the model write correct,
simulatable HDL"* — **not** *"does it synthesize onto real silicon and meet
timing."* The second bar is stricter. Code can simulate perfectly and still fail
to synthesize, or synthesize into something absurdly large. Running the winning
modules through Quartus for resource and timing numbers would close that gap and
is the obvious next step.

Say this out loud rather than letting someone find it.

## The three gates

Each stage runs only if the previous one passed, so a failure is attributable.

| stage | Verilog | VHDL |
|---|---|---|
| lint | `iverilog -g2001 -t null dut.v` | `ghdl -a --std=08 dut.vhdl` |
| elaborate | `iverilog -g2001 -o sim dut.v tb.v` | `ghdl -e --std=08 tb` |
| simulate | `vvp sim` | `ghdl -r --std=08 tb` |

Pass means the simulation printed exactly `ALL TESTS PASSED`.

**Where a model fails is itself a result.** "VHDL attempts die at elaboration
more often" is a more interesting sentence than any single pass rate.

## Fairness, which is the whole ballgame

An unfair comparison is worse than none — it produces a confident number that
means nothing. `CONTRACT.md` is the frozen ruleset. The load-bearing parts:

- the VHDL spec describes **the same circuit** as the Verilog spec — same reset
  polarity and priority, signedness, widths, clock edge, wrap semantics
- both testbenches drive **the same vectors in the same order**
- the specs are **the same length and detail**; explaining more in one language
  would show up in the results as a fake property of that language
- **neither spec hints** at the failure modes being measured
- the two system prompts are structurally identical

## Testbench validation — done before any model ran

A testbench that passes everything measures nothing. Every testbench here was
checked against a correct implementation (must pass) and a deliberately broken
one (must fail), where the breakage is a real LLM mistake that compiles cleanly:

| task | the planted defect |
|---|---|
| `int8_mac` | reset priority inverted — checks `en` before `rst` |
| `dot4_int8` | signed inputs treated as unsigned |
| `mac_array8` | blocking assignment in a clocked process |

**Result: 12/12 correct**, and both languages discriminate identically — which is
the precondition for comparing their pass rates at all. Full log:
[`results/testbench-validation.txt`](results/testbench-validation.txt).

## Running it

```bash
brew install icarus-verilog ghdl
pip install anthropic
export ANTHROPIC_API_KEY=sk-ant-...

python3 harness.py --trials 3                 # both languages
python3 harness.py --lang verilog --trials 5  # one language
python3 harness.py --report                   # table from existing results
```

Results append to `results/results.jsonl`, one JSON object per attempt, with
`lang`, `task`, `model`, `trial`, the three gate booleans, timings, and the
generated code. Append-only, so runs accumulate.

> GHDL installs as a Homebrew **cask** and arrives quarantined — macOS blocks it
> and `ghdl --version` prints nothing at all. Fix:
> `xattr -dr com.apple.quarantine /opt/homebrew/Caskroom/ghdl`

## The tasks

Not toys. These are the building blocks of the int8 MAC array in the project's
fallback path, so benchmarking them produces working modules as a byproduct.

| task | what it is |
|---|---|
| `int8_mac` | signed 8-bit multiply-accumulate, synchronous reset |
| `dot4_int8` | combinational 4-element signed dot product |
| `mac_array8` | 8-wide signed dot product, registered output |
