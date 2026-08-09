# Hardware results — measured on the board

**Status: the model runs on the FPGA and its output is byte-identical to the
golden reference.** 256 tokens, seed 42, no divergence.

Everything on this page was measured on Justin's DE10-Lite on Sunday 9 August
2026, not derived. Where a number here contradicts an estimate elsewhere in the
repo, this page wins and the other page has been corrected.

---

## The headline

| | |
|---|---|
| Tokens generated | **256 of 256** (full run, clean loop exit) |
| Output vs `expected_output.txt` | **byte-identical** (574 bytes, line endings normalised) |
| Wall clock | **261 s** |
| Speed | **1.020 s/token · 0.98 tok/s** |
| ELF | 1,984,108 bytes — text 1,201,836 · data 7,276 · bss 774,996 |
| JTAG load | 1,181 KB in 20.3 s (58.1 KB/s), verified OK |

The story it wrote is the reference story, to the byte:

> Once upon a time, there was a little girl named Lily. She loved to play outside
> in the sun. […] Lily was happy that the ball could read

**There is no float divergence between the board and the macOS reference.** That
was an open worry — the answer is no, they agree exactly for all 256 tokens.

---

## The machine we are actually running on

Read out of `Computer_System.sopcinfo` and the generated `system.h`, not assumed:

| | |
|---|---|
| Core | `Nios2`, `altera_nios2_gen2`, **impl = Fast** (Nios II/f) |
| Clock | **100 MHz** |
| Instruction cache | 4,096 bytes |
| **Data cache** | **0 bytes — there is none** |
| Hardware multiply / divide | present |
| FPU | present, custom instructions 252–255, `-mcustom-fpu-cfg=60-2` |
| SDRAM | 64 MB at `0x00000000` |
| On-chip SRAM | 64 KB at `0x08000000` |

Two things here were not in any plan and both matter.

**1. The system is dual-core.** There are two Nios II cores and two JTAG UARTs
(`Nios2`/`JTAG_UART` and `Nios2_2nd_Core`/`JTAG_UART_2nd_Core`). No `.jdi` ships
with the prebuilt `.sof`, so the tools cannot work out which one you mean and
refuse to connect at all:

```
There are two or more Nios II CPUs with debug modules available which match
the values specified.  Please use the --device and/or --instance parameters
```

Everything must carry `--device 1 --instance 0`. Instance 0 is the core the BSP
targets.

**2. The core has no data cache.** `ALT_CPU_DCACHE_SIZE 0`. Every weight read —
about 259,000 of them per token — is an individual uncached transaction to a
16-bit SDRAM. This single fact explains the entire performance story below.

---

## Speed: measured vs predicted

The repo predicted **0.1–0.2 s/token** with the hardware FPU and 0.7–3.0 on soft
float. The measured answer is **1.02 s/token with the hardware FPU verified
active** — five to ten times slower than predicted, and sitting inside the band
the prediction reserved for software float.

The FPU is genuinely in use. This was checked two ways, because it is the number
most likely to be argued about:

- `ALT_CFLAGS += -mcustom-fpu-cfg=60-2` is present in the generated `public.mk`
- the linked image contains 66 `custom` instructions (opcodes 252–255)

So **"did the FPU flag survive" is the wrong question.** It survived, it is
working, and we are still at ~1 s/token. The estimate was wrong, not the build.

### Where the time goes

Cycle-accurate profile at 100 MHz, 32 tokens, instrumented copy (the repo source
was never modified):

| inside `forward()` | share |
|---|---|
| `matmul` | **48 %** |
| `softmax` | **28 %** |
| `rmsnorm` | 0 % |
| everything else (RoPE, SiLU, residuals, attention loops) | 22 % |

`forward()` costs 382 ms/token at short context. The full-run average is
1,020 ms/token because attention work grows with position and the sampler sits
outside `forward()`. Do not present 382 ms as the per-token cost.

`matmul` measured **722 ns per MAC**, against 259,313 MACs/token — which matches
the documented 259,328 exactly, so the model really is doing the arithmetic we
say it is.

### Why a MAC costs 722 ns on a 100 MHz core

Micro-benchmarks on the board (coarse — see the timer note below):

| | |
|---|---|
| Sequential SDRAM read | 10.9 MB/s · **357 ns per 4-byte read** |
| Dependent float multiply-add, operands in registers | **298 ns** |
| Multiply-add with one operand streamed from SDRAM | 476 ns |

Both halves are slow, and they add rather than overlap: no data cache means no
prefetch and no burst, and the accumulator chain in `matmul` (`val += w * x`)
serialises the FP latency. The real inner loop does *two* uncached loads plus an
index multiply, which lands it at 722 ns.

**Consequence for the accelerator deliverable:** an int8 MAC array attacks the
298 ns, not the 357 ns. With no data cache, feeding it is the harder half of the
problem. Anything that reduces *bytes moved* (int8 weights) is worth more here
than anything that increases arithmetic throughput.

### The other 28 %: `expf` is running in software double precision

`expf`, `powf` and `sqrtf` all call `__adddf3`, `__subdf3`, `__muldf3`,
`__divdf3`, `__extendsfdf2`, `__truncdfsf2`. newlib promotes them to **double**,
and this core has single-precision hardware only — so every one of those is
software emulation.

That is why `softmax` costs 28 % of `forward()` while doing only ~1,150
exponentials per token, and it is why RoPE shows up in "everything else":
upstream calls `powf` **160 times per token** (`dim/2 × n_layers`), recomputing
values that depend only on `i`.

---

## Optimisations available, and what each one costs us

| | gain | keeps byte-exactness? |
|---|---|---|
| Hoist RoPE out of the layer loop | ~5× on RoPE — `cos`/`sin` depend on `(pos, i)` only, so 5 layers recompute identical values | **yes** — same values, computed once |
| Float-only `expf` | large; `softmax` is 28 % of `forward()` | **no** — changes the last ulp, so eventually a different token |
| Unroll `matmul` accumulator | hides FP latency, maybe ~2× on 48 % of `forward()` | **no** — changes FP association order |
| int8 weights | ~4× fewer bytes moved, which is the real bottleneck | **no** — different arithmetic entirely |

Only the first is free. The other three all break *"the math is byte-for-byte
upstream"*, which is the project's headline claim, and would require
regenerating the golden reference and retiring the bit-exactness statement.

**This is a decision for the team, not a technical call.** Recommendation: do the
RoPE hoist, keep bit-exactness, and put the honest 1.02 s/token on the slide. The
gap between what the silicon could do and what we did is a better story than a
number squeezed by giving up the claim that makes the project interesting.

---

## How it was actually built

**No Monitor Program GUI is required.** The whole thing drives from the command
line, which makes it scriptable and reproducible:

```bash
# 1. program the prebuilt system (~4 s)
quartus_pgm -m jtag -o "p;DE10_Lite_Computer.sof"

# 2. generate a HAL BSP against the real system description
nios2-bsp hal ./bsp <path>/DE10-Lite_Computer/verilog --cpu-name Nios2

# 3. build, with the model as a C array -- no .bin, no objcopy
nios2-app-generate-makefile --bsp-dir ./bsp --elf-name llama.elf \
    --src-files run_baremetal.c --set APP_CFLAGS_OPTIMIZATION -O2
make

# 4. run  (--instance 0 is mandatory, see dual-core above)
nios2-terminal --device 1 --instance 0 &
nios2-download -c "USB-Blaster [USB-0]" --device 1 --instance 0 -g llama.elf
```

`nios2-bsp` picks the right answers by itself. It reported:

```
Default linker sections mapped to SDRAM
STDIO character device is JTAG_UART
```

### The linker-region trap did not fire, and here is the proof

The repo warns that `.text`/`.rodata`/`.bss` landing in the 64 KB on-chip RAM
hangs with no error. It is a real trap, but the BSP defaults are already correct
for this system. Verified by *address*, which is stronger than reading a dialog:

| section | size | address | region |
|---|---|---|---|
| `.entry` | 32 | `0x0` | SDRAM |
| `.exceptions` | 552 | `0x20` | SDRAM |
| `.text` | 134,624 | `0x248` | SDRAM |
| `.rodata` | 1,066,628 | `0x21028` | SDRAM ← the model |
| `.rwdata` | 7,276 | `0x125BAC` | SDRAM |
| `.bss` | 774,996 | `0x128FC4` | SDRAM |

On-chip SRAM is at `0x08000000` and nothing is placed there.

---

## Corrections to other pages

- **`stories260K.bin` / `tok512.bin` do not exist and are not needed.** The
  build takes `model260k.h` / `tok512.h` directly. Any instruction sheet still
  listing two `nios2-elf-objcopy` commands describes a build that cannot run —
  the `.bin` files are gitignored and were never in the package.
- **The usable SDRAM linker region is ~32 MiB, not 64 MiB.** `system.h` reports
  `SDRAM_SPAN 67108864`, but the generated region is
  `SDRAM : ORIGIN = 0x20, LENGTH = 33554400`. Irrelevant at our 1.9 MB, worth
  knowing before anyone sizes something against "64 MB".
- **The system clock ticks at 8 Hz** (125 ms). Useless for profiling. A
  timestamp timer was added to the BSP (`hal.timestamp_timer Interval_Timer_2`)
  giving 100 MHz resolution. `time_in_ms()` in `run_baremetal.c` still returns 0
  by design, so the board still cannot self-report tok/s — the 1.02 s/token
  above is external wall clock.

## Two gotchas that cost time

**Stale JTAG UART output.** A previous program keeps running after you close
`nios2-terminal`, and its buffered bytes arrive in the *next* session. It looks
exactly like a corrupted run — you get the middle of an old story spliced onto
the start of a new one. Reset the CPU (`nios2-download -r`) and drain with a
throwaway terminal before any measured run.

**A capture artifact that looked like a hang.** One run appeared to stall at 434
of 578 bytes and stay frozen for 90 s, which looks precisely like the documented
"different words / stops early" failure. It was not: the program was running
fine and the capture stopped. The instrumented build reached
`<LOOP-EXIT pos=256 steps=256>` and produced the complete story. **Before
declaring a hang, confirm the output path, not just the output.**
