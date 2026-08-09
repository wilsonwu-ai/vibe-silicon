# DE10-Nano bring-up

Goal of this half: a measured CPU-only tokens/sec baseline, recorded before
anyone touches Verilog. If this is not done by the 14:00 check-in, drop the FPGA
half and ship the benchmark alone.

## Step 0: confirm which board it is

Read the silkscreen. Three different boards are called "DE10":

| Board | SoC | Runs Linux? | Usable here? |
|---|---|---|---|
| **DE10-Nano** | Cyclone V `5CSEBA6` | yes, dual Cortex-A9 | **yes, this is the plan** |
| **DE10-Standard** | Cyclone V | yes | yes, same plan |
| **DE10-Lite** | MAX 10 | **no ARM at all** | no, abandon the ARM half |

Quick physical check: Nano and Standard have an ethernet jack and a micro-SD
slot. Lite has neither.

## Step 1: shell on the board

Serial console over the mini-USB port, 115200 baud:

```bash
ls /dev/tty.usbserial* /dev/tty.SLAB_USBtoUART 2>/dev/null && screen /dev/tty.usbserial-* 115200
```

Terasic's DE10-Nano Linux console SD image works. A MiSTer SD card also works,
it is Linux underneath.

Once you have a prompt, get on ethernet so you can `ssh` and `scp` instead of
fighting a serial terminal all day. Then confirm the architecture:

```bash
uname -m && nproc && free -m && grep -i features /proc/cpuinfo
```

You want `armv7l`. **32-bit ARM.** Nothing built for `aarch64` will run, and
llama.cpp's good ARM kernels target ARMv8, which is why we are not using it.

## Step 2: llama2.c baseline

```bash
git clone https://github.com/karpathy/llama2.c && cd llama2.c
wget https://huggingface.co/karpathy/tinyllamas/resolve/main/stories15M.bin
make runq
```

Use the **quantized** build (`runq`, Q8_0 int8), not `run`. Int8 maps onto DSP
blocks cleanly; fp32 does not. It is also already ~3x faster and 4x smaller on
the CPU, for free.

Start with **stories15M**, not stories110M. We want fast iterations, not a
better novelist.

```bash
./runq stories15M_q80.bin -n 256 -i "Once upon a time"
```

It prints tok/s at the end. Expect roughly **10 to 30 tok/s**.

> **Write that number in `board/baseline.txt` and commit it.** It is half the
> presentation. Everything after this point is measured against it.

## Step 3: the hook

`runq.c` funnels essentially all inference cycles through one function:

```c
void matmul(float* xout, float* x, float* w, int n, int d)
```

That is the only thing we replace. The FPGA call goes in that function body and
nowhere else.

## Step 4: reaching the fabric from Linux

The Lightweight HPS-to-FPGA bridge is memory-mapped at **`0xFF200000`**. From
userspace, `mmap` `/dev/mem` at that offset and control registers become plain
pointer writes. (The wider HPS-to-FPGA bridge sits at `0xC0000000` if we end up
streaming weights rather than poking registers.)

Sanity-check the bridge with a trivial fabric design (write a value, read it
back) **before** wiring up any MAC array. Debugging "is the bridge alive" and
"is my dot product right" at the same time costs a synthesis slot you do not
have.

## Synthesis budget

Quartus compiles for this part in **15 to 30 minutes**. That is roughly **12 to
15 runs in a working day, total.**

Every module passes `iverilog` simulation before it is allowed to consume a
synthesis slot. Simulation is ~1 second and free. See `bench/` for the harness
that already does this.
