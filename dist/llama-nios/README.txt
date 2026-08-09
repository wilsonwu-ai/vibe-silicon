llama2.c on the DE10-Lite  --  build instructions for Justin
============================================================

New here? Read JUSTIN-START-HERE.txt instead. This file is the short version.

What this is: Karpathy's llama2.c with the operating system removed. Every
neural-network function is byte-for-byte upstream. Only file I/O and memory
allocation were replaced, because the board has no filesystem and no heap.

Verified on macOS before you got it: this source produces output BYTE-IDENTICAL
to upstream run.c. md5 of that output = 8e6e99ed83fc476e1a33bc0940ecffa1
(see expected_output.txt)

Files
-----
  run_baremetal.c      the program
  model260k.h          the model as a C array, 1,056,540 byte payload
  tok512.h             the tokenizer, 6,227 byte payload
  expected_output.txt  exactly what it should print, seed 42
  bridge.py            forwards board output to the public page

There is no filesystem on the board, so the weights are compiled in rather than
loaded. Both headers are declared __attribute__((aligned(8))) so the float*
cast inside read_checkpoint() is legal on a 32-bit core.


BUILD
-----
Use the Intel FPGA Monitor Program, the same way you built the stock sample:

  File > New Project > "DE10-Lite Computer" > C Program
    > source: run_baremetal.c
    > linker settings: .text .rodata .data .bss heap stack ALL in SDRAM
    > Compile

model260k.h and tok512.h must sit next to run_baremetal.c. They already do.

The Monitor Program owns the BSP, the linker script and the stdio-to-JTAG-UART
wiring. A bare nios2-elf-gcc command line has none of that and produces an ELF
that will not boot, so use it only as a compile check:

  nios2-elf-gcc -O2 -mcustom-fpu-cfg=60-2 run_baremetal.c -o llama.elf -lm

If -mcustom-fpu-cfg=60-2 errors, DROP IT. Soft float still works, just slower.
That is a speed problem, not a correctness problem.

Expect a minute or two of compile time. model260k.h is 5.5 MB of hex; gcc is
working, not hung.


RUN
---
Monitor Program: Load, then Run. Or by hand, with nothing else holding the
USB-Blaster:

  quartus_pgm -m jtag -o "p;<path to DE10-Lite_Computer.sof>"
  nios2-download -c "USB-Blaster [USB-0]" -g llama.elf
  nios2-terminal

The .sof must be reprogrammed after every power cycle -- MAX 10 reloads its
factory image from on-chip flash, and the Nios II core goes with it.

Expect 9-70 seconds for the ~1.1 MB ELF to load over JTAG. Then tokens start
appearing one at a time.


IF NOTHING PRINTS -- check this first
-------------------------------------
In the BSP / Monitor Program linker settings, .text .rodata .data .bss heap and
stack must all be in SDRAM (0x00000000, 64 MB) -- NOT the 64 KB on-chip RAM.

This program needs ~1.8 MB, 1 MB of which is the model sitting in .rodata. It
does not fit on-chip, and the failure mode is a HANG WITH NO ERROR MESSAGE.
This is the single most likely way to lose an hour.


WHAT IT SHOULD SAY
------------------
Seed is fixed at 42, so the output is deterministic. First words:

  Once upon a time, there was a little girl named Lily. She loved to play
  outside in the sun. One day, her mom asked her to teach him a nice way to
  play in the sun.

If you get those words, it is working correctly. If you get different words,
the model loaded but something is off -- tell Wilson. If you get garbage or
nothing, it is the linker regions.


TIMING
------
time_in_ms() returns 0 on bare metal, so the tok/s line is suppressed. Use a
stopwatch on 256 tokens and report the number to Wilson. A measured number goes
on the slide; an estimated one does not.


PUTTING IT ON THE PUBLIC PAGE
-----------------------------
The program prints once and exits, so start the bridge BEFORE re-running it.

  shell 1:  python bridge.py --token <TOKEN> --reset
  shell 2:  nios2-download -c "USB-Blaster [USB-0]" -g llama.elf

The bridge spawns its own nios2-terminal, so close any other one first.
