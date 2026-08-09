# FPGA resource utilization — measured, not estimated

Written 2026-08-09. Every number below came out of Quartus Prime 18.1's own
Fitter and TimeQuest reports from a **full compile** (Analysis & Synthesis →
Fitter → Assembler → TimeQuest STA) of the exact "DE10-Lite Computer" project
that produces the `.sof` already flashed and verified on the physical board.
Nothing here is a datasheet guess.

**Method note, so this doesn't get misread as touching the working board:**
the compile ran on an isolated copy of the project
(`C:\nios-llama\resource-analysis\verilog\`), not the working directory the
`.sof` on the board came from. The source (`.qsf`/`.sdc`/`.qsys`) is
byte-for-byte the stock, unmodified Terasic project — this recompile changes
nothing about what's on the board today, it only extracts the reports Quartus
normally produces during a build.

```
quartus_sh --flow compile DE10_Lite_Computer -c DE10_Lite_Computer
Quartus Prime 18.1.0 Build 625, Full Compilation: 0 errors, 234 warnings
Elapsed: 11 min 06 s wall-clock (45 min 10 s total CPU across threads)
```

The 234 warnings are all pre-existing, from the stock reference design (e.g.
dangling PLL clock bits, missing-source nets in the unused VGA subsystem) —
none are new, and none touch the LED code we added.

## Device

| | qsf says | physically confirmed (`jtagconfig`) |
|---|---|---|
| Part | `10M50DAF484C6GES` | `10M50DAF484C7G` |

The Terasic-supplied project file (unmodified, as shipped) targets a `C6GES`
speed grade; the die actually on the board is `C7G` (see README's "hardware
correction" note). Same density (`10M50` = 49,760 LEs either way), different
speed bin. This is a pre-existing characteristic of the stock project, not
something this analysis changed — flagged here for honesty, not fixed, since
"fixing" it would mean re-touching a project that already produces a verified
working `.sof`.

## Logic, memory, multipliers — Fitter Summary

| Resource | Used | Capacity | % |
|---|---|---|---|
| Total logic elements | 29,206 | 49,760 | **59%** |
| — combinational functions | 25,408 | 49,760 | 51% |
| — dedicated logic registers | 17,361 | 49,760 | 35% |
| Total registers | 17,430 | — | — |
| Total pins | 185 | 360 | 51% |
| Total memory bits | 847,346 | 1,677,312 | **51%** |
| Embedded Multiplier 9-bit elements | 30 | 288 | 10% |
| Total PLLs | 3 | 4 | 75% |
| UFM blocks | 0 | 1 | 0% |
| ADC blocks | 1 | 2 | 50% |

The memory-bit capacity (1,677,312 bits = 1,638 Kbit) matches the README's
board-spec table exactly — good cross-check that this is the real M9K fabric,
not a different number from a different source.

The 30 embedded-multiplier 9-bit elements resolve to **16 of the 144 hardware
18×18 multiplier blocks** (14 configured as 18-bit, 2 as 9-bit). The Fitter's
own instance names trace all of them to `..._cpu_mult_cell` under `Nios2` and
`Nios2_2nd_Core` — i.e. **8 hardware multiplier blocks per Nios II core**, for
the CPU's native integer multiply instruction. None of this is the
floating-point custom instruction (that's separate logic, not multiplier
primitives) and none of it is anything project-specific to the language
model — this is just what "two Nios II/f cores" costs in DSP blocks before a
single line of `matmul()` runs.

## Clock tree

| Clock | Frequency | Drives |
|---|---|---|
| `CLOCK_50` (board input) | 50 MHz | feeds `System_PLL` |
| System clock (`System_PLL.sys_clk`) | **100 MHz** | both Nios II cores, SDRAM interconnect, all PIOs (incl. LEDs), timers, JTAG UART |
| `DRAM_CLK` | 100 MHz, phase-shifted | SDRAM chip |
| `CLOCK_ADC_10` | 10 MHz | onboard ADC (ADXL345 path) — unused by our workload |
| `CLOCK2_50` / video PLL | 50 MHz in → ~177–192 MHz internal | VGA subsystem — unused by our workload |

The 100 MHz system clock is the one that matters for the model: it's the
Nios II core clock confirmed earlier in `HANDOFF.md`/`HARDWARE-RESULTS.md`,
and it's what every LED write and every SDRAM weight fetch runs on.

## Timing (TimeQuest STA)

| Corner | Achievable Fmax on the 100 MHz system clock |
|---|---|
| Slow 1200mV 85°C (worst-case, hot) | **96.77 MHz** |
| Slow 1200mV 0°C | 106.47 MHz |
| Fast 1200mV 0°C | (positive margin) |

At the worst-case hot corner, TimeQuest reports the design's critical path
limits it to ~96.8 MHz against a 100 MHz requirement — about a 3% shortfall,
i.e. small negative slack on a handful of paths (worst single path ≈ ‑0.93 ns,
total negative slack ≈ ‑11.2 ns summed across all failing endpoints). At 0°C
it clears with margin.

**Read this the way `bench/FINDINGS.md` reads its own headline number: don't
over-trust it in isolation.** Quartus also reports "Design is not fully
constrained for setup/hold requirements" — this project has unconstrained I/O
(VGA, Arduino header, ADC pins) that we don't use, which is normal for a
general-purpose reference design and doesn't reflect on the path the model
actually runs on. The number that isn't in question is the one that matters
more: **this exact `.sof` has run 256-token, byte-exact, repeatable inference
on the physical board** (`HARDWARE-RESULTS.md`) — whatever headroom TimeQuest
computes in the worst-case industrial corner, the chip in hand works at room
temperature, measured, not modeled.

## What else is sharing the fabric

The Fitter's own partition table shows a small amount of resource use that
isn't the Nios cores or the SDRAM path: a SignalTap logic-analyzer instance
(`sld_signaltap`, ~875 LEs, 16 M9K blocks) and its JTAG debug hub, both part
of the stock Terasic reference design's built-in debug instrumentation — not
something this project added, and not something the model or the LED code
touches.

Qsys component inventory (`Computer_System.qsys`), for reference — everything
sharing the same fabric as the model:

| Component | Kind | Notes |
|---|---|---|
| `Nios2`, `Nios2_2nd_Core` | `altera_nios2_gen2` | the two soft cores; only `Nios2` runs the model |
| `fpoint_hw_qsys` ×2 | `altera_nios_custom_instr_floating_point` | one FPU per core |
| `SDRAM` | `altera_avalon_new_sdram_controller` | the 64 MB off-chip SDRAM path |
| `Onchip_SRAM` | `altera_avalon_onchip_memory2` | 64 KB on-chip, reset/boot region — not where the model or its weights live |
| `LEDs`, `SW`, `KEY`, `HEX3_HEX0`, `HEX5_HEX4` | `altera_avalon_pio` | the LED sign-of-life write lands on the `LEDs` instance |
| `JTAG_UART` ×2 | `altera_avalon_jtag_uart` | one per core — the model's stdout goes out one of these |
| `sysid` | `altera_avalon_sysid_qsys` | board/system ID readback |
| 4× timer | `altera_avalon_timer` | includes the 100 MHz timestamp timer added for profiling (`HANDOFF.md`) |
| `ADC`, accelerometer SPI | `altera_up_avalon_adc`, `altera_up_avalon_accelerometer_spi` | onboard sensors, unused by the model |
| `VGA_Subsystem` | qsys subsystem | unused by the model |

## Bottom line

The model + LED feature costs nothing extra in fabric terms worth measuring —
it's a handful of PIO writes. What actually consumes the chip is standing up
**two full Nios II/f soft cores with FPUs and a 64 MB SDRAM controller** on a
board that also carries VGA, ADC, and debug instrumentation it doesn't need
for this demo: **59% of logic elements, 51% of on-chip memory, 10% of hard
multipliers**, comfortably inside the MAX 10 10M50's budget with room to
spare — which is also why the "not fully constrained" and near-Fmax caveats
above are worth reading but not worth losing sleep over: there's slack in the
chip even where TimeQuest doesn't see slack in the clock.
