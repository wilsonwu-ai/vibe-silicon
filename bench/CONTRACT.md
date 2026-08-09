# Dual-language benchmark contract (FROZEN)

The question this benchmark answers:

> Given the **same specification**, how much worse are LLMs at VHDL than at Verilog?

That comparison is only worth anything if the two sides are genuinely matched.
An unfair comparison is worse than no comparison, because it produces a
confident number that means nothing. Everything below exists to keep them fair.

## Layout

```
bench/tasks/<task>/
    spec.md         Verilog spec   (exists)
    tb.v            Verilog testbench, module `tb`   (exists)
    spec_vhdl.md    VHDL spec      (new)
    tb.vhdl         VHDL testbench, entity `tb`      (new)
    ref.v           known-good Verilog  (new, for validating the testbench)
    ref.vhdl        known-good VHDL     (new)
    bad.v           deliberately-broken Verilog (new)
    bad.vhdl        deliberately-broken VHDL    (new)
```

## Fairness rules — these are what make the number mean something

1. **Identical behaviour.** The VHDL spec must describe exactly the same circuit
   as the Verilog spec: same reset polarity and priority, same signedness, same
   widths, same clock edge, same wrap-on-overflow semantics.
2. **Identical test vectors.** `tb.vhdl` must drive the same stimulus values in
   the same order as `tb.v`, and check the same expected results. If one side
   tests `-128 * -128` and the other does not, the comparison is dead.
3. **Comparable prose.** The two spec files should be the same length and the
   same level of detail. Do not helpfully explain more in one language than the
   other. The only legitimate differences are the port declaration block and
   language-specific type names.
4. **No hints.** Neither spec may mention the failure modes we are measuring —
   do not write "remember to use signed" or "beware latch inference". That is
   the thing under test.

## Grading gates

Three stages, each only runs if the previous one passed. Same shape in both
languages so the columns are comparable.

| stage | Verilog | VHDL |
|---|---|---|
| lint | `iverilog -g2001 -t null dut.v` | `ghdl -a --std=08 dut.vhdl` |
| elaborate | `iverilog -g2001 -o sim dut.v tb.v` | `ghdl -a --std=08 tb.vhdl` then `ghdl -e --std=08 tb` |
| simulate | `vvp sim` | `ghdl -r --std=08 tb` |

**Pass criterion, both languages:** the simulation prints the exact string
`ALL TESTS PASSED`. A testbench must print that only when every check passed.

VHDL testbenches must terminate themselves (`std.env.finish` or a stopped clock
process). A hung simulation is a failure, not a pass — the harness timeout
treats it as one, but do not rely on that.

## Testbench validation — non-negotiable

**A testbench that passes everything measures nothing.** Before either testbench
is trusted, it must be run against two implementations:

- `ref.*` — a correct implementation. Must print `ALL TESTS PASSED`.
- `bad.*` — a *plausibly* wrong implementation. Must NOT print it.

`bad.*` must fail for a reason an LLM actually gets wrong, not a syntax error.
Good candidates, one per task:

- signed vs unsigned (treating `signed [7:0]` / `signed` as unsigned)
- blocking vs non-blocking assignment (`=` vs `<=` in a clocked process)
- reset priority inverted (checking `en` before `rst`)
- latch inference from an incomplete `if` with no `else`
- off-by-one in an accumulate or shift

Record which failure mode each `bad.*` encodes. That taxonomy is a result in
itself — "VHDL submissions failed on signedness 3× more often than Verilog" is a
more interesting sentence than any single pass rate.

## System prompts

Structurally identical, differing only where the language forces it. The Verilog
one already exists in `harness.py`. The VHDL one must:

- ask for exactly one `entity` + `architecture` pair and nothing else
- require synthesizable constructs only
- name the same FPGA target
- require ports to match the spec exactly by name, direction and width
- be the same length and tone as the Verilog prompt

## Results schema

One JSON object per attempt, appended to `bench/results/results.jsonl`:

```json
{"ts":"...","lang":"vhdl","task":"int8_mac","model":"claude-opus-5","trial":0,
 "lints":true,"elaborates":true,"passes":false,
 "seconds":12.4,"output_tokens":812,"log":"...","code":"..."}
```

`lang` is the new field. Everything else keeps its current meaning so old rows
stay readable.
