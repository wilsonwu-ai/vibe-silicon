Write a signed 8-bit multiply-accumulate unit.

```
module int8_mac (
    input  wire               clk,
    input  wire               rst,   // synchronous, active high
    input  wire               en,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg  signed [31:0] acc
);
```

Behavior, all on the rising edge of `clk`:

- If `rst` is high, `acc` becomes 0. Reset takes priority over `en`.
- Else if `en` is high, `acc` becomes `acc + (a * b)`.
- Else `acc` holds its current value.

The product `a * b` must be a signed multiply. Accumulation is in 32-bit signed
arithmetic and is allowed to wrap.
