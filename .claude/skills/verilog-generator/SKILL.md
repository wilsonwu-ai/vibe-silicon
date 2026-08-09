---
name: verilog-generator
description: Generates a single synthesizable Verilog-2001/2005 module from a spec, natural language description, or interface definition. Enforces strict pre-SystemVerilog syntax, reg/wire discipline, latch-free combinational logic, and Intel MAX 10 inference patterns. Use when asked to generate, write, implement, or fix a Verilog module in vibe-silicon — including bench/tasks specs.
license: MIT
metadata:
  upstream: https://github.com/bjwanneng/verilog-generator
  upstream_commit: bfb538ad762e579558d0845ab710479c06590c82
  localized_for: vibe-silicon (Intel MAX 10 / iverilog -g2001)
  version: "1.0.0-vibe-silicon"
  category: hardware-design
---

# verilog-generator (vibe-silicon)

Generates a single synthesizable Verilog module targeting this repo's toolchain.

## THE GATE

Every module is judged by `bench/harness.py`, which runs exactly this:

```
iverilog -g2001 -t null dut.v            # 1. lints standalone
iverilog -g2001 -o sim dut.v tb.v        # 2. elaborates against the hand-written testbench
vvp sim                                  # 3. must print ALL TESTS PASSED
```

Three consequences that override everything else in this skill:

1. **`-g2001` means Verilog-2001.** Not SystemVerilog. Not `logic`, not `always_ff`.
   A single SystemVerilog token fails at step 1 and scores zero.
2. **The testbench is hand-written and you never see it.** It instantiates the DUT by
   module name with named port connections. Any deviation in module name, port name,
   width, or signedness fails at step 2.
3. **`vvp` must print `ALL TESTS PASSED`.** Functional correctness is checked, not just
   syntax. A module that compiles but computes the wrong value scores zero.

## RULE 0 — THE PORT CONTRACT IS VERBATIM (highest priority)

When the spec supplies a module header — as every `bench/tasks/*/spec.md` does —
**reproduce it exactly, character for character**, before writing any body:

- Module name exactly as given (`int8_mac`, not `int8_mac_unit`)
- Port names exactly as given (`a`, `b`, `acc`, `clk`, `rst`, `en`)
- Port order, widths, and `signed` keywords exactly as given
- `input wire` / `output reg` exactly as given

**This rule overrides the lowRISC style guide.** In particular:

| Style guide says | Spec says | Winner |
|---|---|---|
| `_i` / `_o` port suffixes | bare `a`, `b`, `acc` | **spec** |
| outputs are `wire`, driven by `assign` | `output reg signed [31:0] acc` | **spec** |
| `ALL_CAPS` parameters | whatever the spec shows | **spec** |

The style guide applies to everything the spec does *not* pin down: internal signal
naming, indentation, block structure, case defaults, reset placement.

Never rename a port to match house style. The testbench does not care about your style.

## MANDATORY RULES

**Non-negotiable. Violating any one is a critical error requiring regeneration.**

### Rule 1: Verilog-2001/2005 syntax only
- NEVER use `logic`, `always_ff`, `always_comb`, `always_latch`, `interface`, `modport`,
  `unique case`, `priority case`, `typedef enum`, `int`, `bit`
- NEVER declare `reg`/`wire` inside an unnamed `begin...end` block
- NEVER forward-reference — declare every signal above the line that first uses it
- Use `localparam [N:0] STATE_X = N'd0, ...` for state encodings, never `typedef enum`

### Rule 2: Correct reg/wire usage
- `reg` for signals driven by `always` blocks; `wire` for signals driven by `assign`
  or by a submodule output
- NEVER drive a `reg` with `assign`; NEVER drive a `wire` from an `always` block
- If the spec declares `output reg`, drive it from an `always` block — do not add an
  internal register and `assign` it out

### Rule 3: No placeholder code
- NEVER emit `// TODO`, `// placeholder`, `// implement later`, or an empty body
- Every module must be complete and synthesizable as written

### Rule 4: Exactly one driver per signal
- A signal is driven by `always` OR `assign`, never both, never from two blocks

### Rule 5: No simulation constructs in the module
- NEVER use `$display`, `$finish`, `$monitor`, `#delay`, or `initial` inside the module
- The bench supplies its own testbench. Do not write one unless explicitly asked.
- Exception: `initial` for parameter validation only

### Rule 6: Reset semantics come from the spec
This repo's specs use **synchronous, active-high** reset with **priority over enable**:

```verilog
always @(posedge clk) begin
    if (rst)      acc <= 32'sd0;   // reset wins
    else if (en)  acc <= acc + a*b;
    // else: hold — no assignment needed
end
```

Read the spec's reset wording every time; do not assume. Never write an async reset
(`always @(posedge clk or posedge rst)`) unless the spec asks for one.

### Rule 7: Signed arithmetic is explicit
This project is int8 inference — signed correctness is the whole game.

- Declare signed ports/regs with the `signed` keyword as the spec shows
- Use `$signed()` when converting an unsigned expression into signed context
- A signed × signed multiply requires **both** operands signed; if either is unsigned
  the result is computed unsigned and silently wrong
- Sign-extend explicitly when widening: `{{24{a[7]}}, a}`, not `{24'd0, a}`
- Wrapping accumulation is usually intended — do not add saturation unless asked

### Rule 8: Self-check before output
Verify every rule below before emitting the final code block. Fix violations silently
and re-verify. Only output code that passes.

## WORKFLOW

### Step 1 — Interface

Restate the interface you are about to implement:

```
## Interface

Module: <exact name from spec>
Parameters:
  <none, or as specified>
Ports:
  input  wire               clk
  input  wire               rst
  ...
Source: verbatim from bench/tasks/<task>/spec.md   (or: derived from description)
```

If the spec pinned the header, say **verbatim** and diff it mentally against the spec
before continuing. If you derived it yourself, say **derived** and flag any guess.

### Step 2 — Code + self-check

```verilog
module <name> (
    input  wire               clk,
    ...
);

    // --- internal signals ---

    // --- logic ---

endmodule
```

Then the checklist:

```
## Self-check

[PASS/FAIL] Port contract matches spec verbatim (name, order, width, signed, reg/wire)
[PASS/FAIL] Verilog-2001 only — no SystemVerilog tokens
[PASS/FAIL] reg/wire driver discipline
[PASS/FAIL] No forward references
[PASS/FAIL] Single driver per signal
[PASS/FAIL] No placeholders
[PASS/FAIL] Bit widths match on every assignment and port connection
[PASS/FAIL] No inferred latches (every always @* path assigns every output)
[PASS/FAIL] Reset polarity/sync/priority match the spec wording
[PASS/FAIL] Signed arithmetic explicit; sign-extension not zero-extension
[PASS/WARN] Reset coverage (list any register left unreset, with reason)
[PASS/WARN/N/A] MAX 10 inference (DSP / M9K) as intended
```

Any `[FAIL]` → fix and regenerate before showing output.

## FILE STRUCTURE — read this before adding directives

Upstream wraps modules in `` `resetall `` / `` `timescale `` / `` `default_nettype none ``
plus a header comment block. **For bench tasks, all of that is discarded**:
`harness.py:extract_verilog` trims everything before the first `module` and after the
last `endmodule`.

- **Bench task output** (`bench/tasks/*`): emit the bare module. Directives are dead
  weight, and `` `default_nettype none `` will *not* protect you there — so be
  disciplined about declaring every net explicitly yourself.
- **Checked-in RTL** (files that live in the repo and feed Quartus): the full wrapper
  is worth having. Use `` `default_nettype none `` before the module and `` `resetall ``
  after `endmodule` to catch typo'd implicit wires at compile time.

## TARGET: Intel MAX 10 `10M50DAF484C7G`

Synthesis is Quartus Prime Lite 18.1. Budget:

| Resource | Available | Notes |
|---|---|---|
| Logic elements | 50 K | |
| Embedded multipliers | **144 × 18×18** | an 8×8 signed multiply fits one |
| M9K block RAM | 1,638 Kbit ≈ **205 KB** | on-chip only |
| External SDRAM | 64 MB | needs a controller; not inferred |

Inference guidance:

- **Multipliers** — a plain `a * b` on signed 8-bit operands infers one 18×18 DSP.
  Do not hand-build shift-add multipliers; Quartus does it better and you have 144.
  A MAC array wider than 144 parallel products will not fit — time-multiplex instead.
- **Memory** — infer M9K with a simple synchronous-read array; a registered read
  address is what makes it a block RAM rather than a wall of registers:
  ```verilog
  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  always @(posedge clk) begin
      if (we) mem[waddr] <= wdata;
      rdata <= mem[raddr];        // registered read → M9K
  end
  ```
  An asynchronous read (`assign rdata = mem[raddr];`) forces distributed logic and will
  blow the LE budget fast.
- **Reset** — do not reset large memory arrays; MAX 10 has no mass-clear. Leave them
  unreset and note it under reset coverage.
- **No hard processor.** There is no ARM/HPS on this part. Everything is fabric.

## CODING STYLE

`coding_style.md` sits next to this file — a Verilog-2001 style guide adapted from
lowRISC. **Read it before generating a module**, and apply it to everything Rule 0
leaves open.

Precedence, highest first:

1. The spec's literal port header (Rule 0)
2. The mandatory rules above
3. A user-supplied `.md` rule file or `.v` template, if given
4. `coding_style.md`

If a style rule would force a syntax violation, syntax wins — note it as
`[WARN] style rule overridden by Verilog-2001 syntax requirement`.

## COMMON ERRORS

| Error | Cause | Fix |
|---|---|---|
| `Variable 'X' cannot be driven by continuous assignment` | `reg` driven by `assign` | make it `wire`, or drive from `always` |
| `Unable to bind wire/reg/memory 'X'` | forward reference, or port name mismatch with the testbench | declare before use; re-check the spec header |
| `Variable declaration in unnamed block requires SystemVerilog` | `reg` inside unnamed `begin...end` | hoist declaration to module level |
| `Multiple drivers on signal 'X'` | both `always` and `assign` drive X | pick one |
| Compiles, wrong results on negative inputs | one multiply operand unsigned | declare both `signed`, or wrap in `$signed()` |
| Compiles, wrong results after widening | zero-extension instead of sign-extension | `{{N{x[MSB]}}, x}` |
| Latch inferred for 'X' | missing assignment on some `always @*` path | assign defaults at the top of the block |
| Design will not fit / LE explosion | async-read memory, or hand-rolled multipliers | register the read address; use `*` |

## ATTRIBUTION

Derived from [bjwanneng/verilog-generator](https://github.com/bjwanneng/verilog-generator)
(MIT), commit `bfb538a`, retrieved 2026-08-09. `coding_style.md` is upstream verbatim.
`SKILL.md` was rewritten for this repo: output language switched to English, the
`iverilog -g2001` harness contract and verbatim port rule added, signed-arithmetic and
MAX 10 inference sections added, and upstream's AXI4 handshake rules removed as
irrelevant to this project — recover them from upstream if an AXI interface is ever needed.
