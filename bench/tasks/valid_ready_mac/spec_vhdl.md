Write a small valid/ready-handshake multiply-accumulate unit: it accepts one
signed 8x8 operand pair at a time on an input handshake, and produces a
running accumulated total on an output handshake.

```
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vr_mac is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;  -- synchronous, active high
        in_valid  : in  std_logic;
        in_ready  : out std_logic;
        a         : in  signed(7 downto 0);
        b         : in  signed(7 downto 0);
        out_valid : out std_logic;
        out_ready : in  std_logic;
        y         : out signed(31 downto 0)
    );
end entity vr_mac;
```

A transfer on either channel happens on a rising edge of `clk` where both
that channel's `valid` and `ready` are '1' (input: `in_valid` and
`in_ready`; output: `out_valid` and `out_ready`).

Behavior, all synchronous. `rst` takes priority over everything below and
returns the unit to its power-on state: idle, `in_ready` '1', `out_valid`
'0', running total 0.

- **Idle.** `in_ready` is '1', `out_valid` is '0'. When an input transfer
  happens, latch `a` and `b` and begin computing; `in_ready` goes '0'.
- **Computing.** Two cycles after the input transfer -- one cycle to
  register the signed product `a * b`, one more to add it into the running
  total and present the result -- `y` becomes the new running total and
  `out_valid` goes '1'. `in_ready` stays '0' the whole time; only one
  operand pair is in flight at a time.
- **Presenting.** Once `out_valid` is '1', `y` and `out_valid` must not
  change until the output transfer happens. When it happens, the unit
  returns to idle and is ready for the next input.

The running total is 32-bit signed and wraps on overflow, same as a plain
accumulator.
