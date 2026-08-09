Write a small valid/ready-handshake multiply-accumulate unit: it accepts one
signed 8x8 operand pair at a time on an input handshake, and produces a
running accumulated total on an output handshake.

```
module vr_mac (
    input  wire               clk,
    input  wire                rst,        // synchronous, active high
    input  wire                in_valid,
    output reg                  in_ready,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg                  out_valid,
    input  wire                out_ready,
    output reg  signed [31:0] y
);
```

A transfer on either channel happens on a rising edge of `clk` where both
that channel's `valid` and `ready` are high (input: `in_valid` and
`in_ready`; output: `out_valid` and `out_ready`).

Behavior, all synchronous. `rst` takes priority over everything below and
returns the unit to its power-on state: idle, `in_ready` high, `out_valid`
low, running total 0.

- **Idle.** `in_ready` is high, `out_valid` is low. When an input transfer
  happens, latch `a` and `b` and begin computing; `in_ready` goes low.
- **Computing.** Two cycles after the input transfer -- one cycle to register
  the signed product `a * b`, one more to add it into the running total and
  present the result -- `y` becomes the new running total and `out_valid`
  goes high. `in_ready` stays low the whole time; only one operand pair is in
  flight at a time.
- **Presenting.** Once `out_valid` is high, `y` and `out_valid` must not
  change until the output transfer happens. When it happens, the unit
  returns to idle and is ready for the next input.

The running total is 32-bit signed and wraps on overflow, same as a plain
accumulator.
