llama2.c on the DE10-Lite  --  build instructions for Justin
============================================================

What this is: Karpathy's llama2.c with the operating system removed. Every
neural-network function is byte-for-byte upstream. Only file I/O and memory
allocation were replaced, because the board has no filesystem and no heap.

Verified on macOS before you got it: this source produces output BYTE-IDENTICAL
to upstream run.c. md5 = 8e6e99ed83fc476e1a33bc0940ecffa1 (see expected_output.txt)

Files
-----
  run_baremetal.c      the program
  stories260K.bin      the model, 1,056,540 bytes
  tok512.bin           the tokenizer, 6,227 bytes
  expected_output.txt  exactly what it should print, seed 42


BUILD
-----
Run these in a Nios II Command Shell, IN THIS DIRECTORY.

  nios2-elf-objcopy -I binary -O elf32-littlenios2 -B nios2 stories260K.bin model.o
  nios2-elf-objcopy -I binary -O elf32-littlenios2 -B nios2 tok512.bin     tok.o
  nios2-elf-gcc -O2 -mcustom-fpu-cfg=60-2 run_baremetal.c model.o tok.o -o llama.elf -lm

  *** cd INTO THIS FOLDER FIRST. ***
  objcopy builds the symbol name from the PATH you give it. Passing
  "models/stories260K.bin" produces _binary_models_stories260K_bin_start,
  which will not link. A bare filename produces the name the C file expects:
  _binary_stories260K_bin_start.

If -mcustom-fpu-cfg=60-2 errors, DROP IT. Soft float still works, just slower.
That is a speed problem, not a correctness problem.


RUN
---
  nios2-download -c "USB-Blaster [USB-0]" -g llama.elf
  nios2-terminal

Expect 9-70 seconds for the ~1.1 MB ELF to load over JTAG. Then tokens start
appearing one at a time.


IF NOTHING PRINTS -- check this first
-------------------------------------
In the BSP / Monitor Program linker settings, .text .rodata .data .bss heap and
stack must all be in SDRAM (0x00000000, 64 MB) -- NOT the 64 KB on-chip RAM.

This program needs ~1.8 MB. It does not fit on-chip, and the failure mode is a
HANG WITH NO ERROR MESSAGE. This is the single most likely way to lose an hour.


WHAT IT SHOULD SAY
------------------
Seed is fixed at 42, so the output is deterministic. First words:

  Once upon a time, there was a little girl named Lily. She loved to play
  outside in the sun. One day, her mom asked her to teach him a nice way to
  play in the sun.

If you get those words, it is working correctly. If you get different words,
the model loaded but something is wrong with the float math -- tell Wilson.
If you get garbage or nothing, it is the linker regions.


TIMING
------
time_in_ms() returns 0 on bare metal, so the tok/s line is suppressed. Use a
stopwatch on 256 tokens and report the number to Wilson. A measured number goes
on the slide; an estimated one does not.
