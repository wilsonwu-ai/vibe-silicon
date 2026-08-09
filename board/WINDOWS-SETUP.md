# Windows setup — second build machine

For getting a second Windows laptop compiling, so the build loop and the board
are not stuck on one machine.

## Why a second machine helps

**Compiling does not need the board.** `nios2-elf-gcc` produces `llama.elf` with
no hardware attached. So the work splits cleanly:

```
  build machine                      board machine
  ─────────────                      ─────────────
  edit C, compile llama.elf   ──►    nios2-download -g llama.elf
  iterate in seconds                 nios2-terminal, measure s/token
```

The ELF hands over through this repo. Two people working, one board.

It is also the insurance the PRD asks for: a second machine that can at least run
the Programmer means a dead laptop at 19:00 is an inconvenience, not the end.

---

## 1. Download first. Everything else waits.

**Quartus Prime Lite 18.1**, Windows, from the **Individual Files** tab:

| file | size |
|---|---|
| base installer | ~1.7 GB |
| `max10-18.1.0.625.qdz` | ~331 MB |

- **Skip ModelSim.** Large, slow, not needed.
- **Skip every other device family.** We only target MAX 10.
- Needs ~14 GB free disk.

**Why 18.1 and not the current release** — this is the whole reason:

| version | Nios II | Windows toolchain |
|---|---|---|
| **18.1 Lite** | ✅ | ✅ self-contained, bundled Cygwin |
| 19.1 – 23.1std | ✅ | ⚠️ needs **WSL 1** (WSL 2 unsupported) + Ubuntu 18.04 + manual Eclipse |
| ≥ 24.1std | ❌ **removed** | — |

Intel dropped the bundled Cygwin at Standard 19.1 and removed the Nios II IP core
entirely at 24.1. 18.1 is the last version where this is a plain Windows install
with nothing else to configure.

**Plain Windows. No WSL, no Linux, no VM.**

## 2. During install — tick Nios II EDS

It is a checkbox. A custom or minimal install can drop it silently, and you end
up having done everything right with no compiler.

Verify afterwards, in a **Nios II Command Shell**:

```
nios2-elf-gcc --version
```

If that works, you are done with the installer. If it does not, the component was
not installed.

## 3. Monitor Program 18.1

Separate download from [fpgacademy.org/tools.html](https://fpgacademy.org/tools.html).

This is what carries the prebuilt **DE10-Lite Computer** — a ready-made Nios II/f
system with hardware floating point, an SDRAM controller mapping all 64 MB, and a
JTAG UART. It is why we are not building an SoC.

## 4. You can coexist with a newer Quartus

18.1 installs to `C:\intelFPGA_lite\18.1` and does not touch an existing 24.1 or
25.1. **Do not uninstall anything** — that only costs time and loses a working
Programmer.

---

## While the download runs

Neither of these needs Quartus or the board.

### Test the public demo path

```bat
git clone https://github.com/wilsonwu-ai/vibe-silicon
cd vibe-silicon\dist\llama-nios
python bridge.py --token <TOKEN> --replay expected_output.txt --cps 12
```

Open https://vibe-silicon.wilson-af8.workers.dev — words should appear, labelled
**"streaming · recorded run"** because that is what it is. Proves the whole
network path from this machine before hardware is involved.

Standard library only. Nothing to `pip install`.

### Poke at CPUlator

[cpulator.01xz.net/?sys=nios-de10-lite](https://cpulator.01xz.net/?sys=nios-de10-lite)
is a browser simulator of **this exact machine** — Nios II on a DE10-Lite. No
install, no hardware.

Useful for a hello-world sanity check. **Keep it off the critical path**: a 1 MB
embedded weight array against an in-browser compiler is unverified, and it is not
where the real answer comes from.

---

## Building once the toolchain exists

In a Nios II Command Shell, **cd into `dist/llama-nios/`**:

```bat
nios2-elf-objcopy -I binary -O elf32-littlenios2 -B nios2 stories260K.bin model.o
nios2-elf-objcopy -I binary -O elf32-littlenios2 -B nios2 tok512.bin     tok.o
nios2-elf-gcc -O2 -mcustom-fpu-cfg=60-2 run_baremetal.c model.o tok.o -o llama.elf -lm
```

**`cd` into the folder first.** `objcopy` builds the symbol name from the path you
give it. `dist\llama-nios\stories260K.bin` produces
`_binary_dist_llama_nios_stories260K_bin_start`, which will not link. A bare
filename gives `_binary_stories260K_bin_start`, which is what the C expects.

If `-mcustom-fpu-cfg=60-2` errors, **drop it**. Soft float still works, roughly
10–20× slower. Speed problem, not a correctness problem.

Hand `llama.elf` to whoever has the board, or commit it.

## The one setting that hangs with no error

In the BSP / Monitor Program linker settings, `.text`, `.rodata`, `.data`,
`.bss`, heap and stack must be in **SDRAM (`0x00000000`, 64 MB)** — not the 64 KB
on-chip RAM.

This program needs ~1.8 MB. It does not fit on-chip, and the failure mode is a
**hang with no error message**. If nothing prints, check this before anything else.

## Expected output

Seed is fixed at 42, so it is deterministic:

> Once upon a time, there was a little girl named Lily. She loved to play outside
> in the sun. One day, her mom asked her to teach him a nice way to play in the
> sun.

Full text in `expected_output.txt`.

| what you see | what it means |
|---|---|
| those exact words | working — time 256 tokens with a stopwatch and report it |
| different words | model loaded, float math is off |
| garbage or nothing | linker regions, see above |
