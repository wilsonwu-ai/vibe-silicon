# `accel-fpga` — the LLM-written accelerator, on real silicon

A standalone, throwaway Quartus project. It has never touched, opened, or
resynthesized the DE10-Lite Computer / Nios II project that runs the
language-model demo — different directory, different `.sof`, different
`TOP_LEVEL_ENTITY`. Programming it temporarily replaces whatever's on the
chip; programming `DE10_Lite_Computer.sof` back afterward restores the demo.

**Status, 2026-08-09: built, programmed, and confirmed passing on the actual
board.** LEDR[9:0] came up steady-on after the self-test ran. This closes the
last open row in the top-level README's "what's ours, what's Intel's, what's
LLM-written" table.

## What it is

`mac_array8`, an 8-wide signed 8-bit dot product, wired into a top-level that:

1. Drives the module through the same 10 checks `bench/tasks/mac_array8/tb.v`
   already proves in simulation — same vectors, same order, same expected
   values. No new test data was invented for hardware.
2. Compares the result against those expected values *inside the FPGA*.
3. Shows the result on `LEDR[9:0]`, readable at a glance, no switches to set:
   - **off** — not yet run (just after power-up)
   - **chasing** (one lit LED walking the row) — self-test running. Paced at
     ~4 Hz by a clock divider so it's actually visible; at the raw 50 MHz
     clock all 10 checks finish in under a microsecond.
   - **steady on, all 10** — PASS
   - **blinking, all 10** — FAIL (sticky; stays failed until `KEY0`)
4. `KEY0` (active-low pushbutton) re-arms and re-runs the whole sequence.

## Whose Verilog is this

Not `bench/tasks/mac_array8/ref.v` — that file's own header says it exists
"only to prove tb.v accepts correct work" (hand-written, not model output).

`mac_array8.v` here is copied verbatim from `bench/results/results.jsonl`:
`{"task": "mac_array8", "lang": "verilog", "model": "claude-sonnet-5",
"trial": 0, "ts": "2026-08-09T17:33:09+00:00"}` — an LLM output that already
passed `tb.v` in simulation at generation time. Human-reviewed here before
synthesis: synchronous reset with priority over `en`, no latches, `$signed()`
cast on every product. Structurally identical in shape to the other two
simulation-passing candidates from Opus 5 and Haiku 4.5 (all three
independently converged on the same 8×`$signed`-multiply-then-sum design).

## Files

| file | what |
|---|---|
| `mac_array8.v` | the LLM-generated accelerator (provenance above) |
| `accel_selftest_top.v` | top-level: sequencer FSM, LED chase/pass/fail display, `KEY0` handling |
| `tb_selftest_top.v` | sim-only sanity check for the top-level, run before ever opening Quartus |
| `accel_selftest_top.qsf` | pins + device (`10M50DAF484C6GES`) |
| `accel_selftest_top.qpf` | Quartus project file |
| `accel_selftest_top.sdc` | real 50 MHz clock constraint (without it, the Timing Analyzer checks against a fictitious 1 GHz default and reports false failures) |

## Device and pins

`DEVICE = 10M50DAF484C6GES` — not the top-level README's photo-derived
`10M50DAF484C7G`. This project instead copies the device string from
`C:\intelFPGA_lite\18.1\University_Program\Computer_Systems\DE10-Lite\DE10-Lite_Computer\verilog\DE10_Lite_Computer.qsf`,
the golden project whose bitstream is the one actually measured running on
this exact board in `docs/HARDWARE-RESULTS.md`. `jtagconfig` on this machine
confirms it too: JTAG ID `031050DD` reports as
`10M50DA(.|ES)/10M50DC`.

Pins cross-checked byte-for-byte between `docs/DE10-Lite_User_Manual.pdf`
(Tables 3-2, 3-3, 3-5) and that same golden `.qsf` — not guessed:

| signal | pin | notes |
|---|---|---|
| `CLOCK_50` | `PIN_P11` | 50 MHz, 3.3-V LVTTL |
| `KEY0` | `PIN_B8` | 3.3V Schmitt trigger, active-low (pressed = 0) |
| `LEDR[9:0]` | `A8,A9,A10,B10,D13,C13,E14,D14,A11,B11` | 3.3-V LVTTL, active-high |

`KEY1`/`PIN_A7` and all `SW`/`GPIO` pins are unused and left off this
project's port list entirely.

## Reproducing the build

```
cd board/accel-fpga
iverilog -g2001 -o s mac_array8.v accel_selftest_top.v tb_selftest_top.v && vvp s
# expect: ALL TESTS PASSED

"C:\intelFPGA_lite\18.1\quartus\bin64\quartus_sh.exe" --flow compile accel_selftest_top
# expect: 0 errors; output_files\accel_selftest_top.sof produced
```

Resource usage (from `output_files/accel_selftest_top.fit.summary`): 262
logic elements (<1% of 49,760), 8 embedded multiplier elements (3% of 288),
0 memory bits, 0 PLLs. Timing closes against the real 50 MHz clock (worst-case
setup slack +3.3 ns).

## Programming and restoring

```
# program the self-test bitstream
quartus_pgm -c "USB-Blaster [USB-0]" -m jtag -o "p;output_files\accel_selftest_top.sof"

# look at LEDR[9:0] -- chase, then steady-on (pass) or blinking (fail)

# restore the language-model demo -- do this before anyone else needs the board
quartus_pgm -c "USB-Blaster [USB-0]" -m jtag -o "p;C:\intelFPGA_lite\18.1\University_Program\Computer_Systems\DE10-Lite\DE10-Lite_Computer\verilog\DE10_Lite_Computer.sof"
```
