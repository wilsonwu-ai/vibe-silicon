Write an 8-wide signed 8-bit dot product with a registered output. This is the
core of the GEMV accelerator, so it must map onto DSP blocks.

```
module mac_array8 (
    input  wire               clk,
    input  wire               rst,     // synchronous, active high
    input  wire               en,
    input  wire        [63:0] a_flat,
    input  wire        [63:0] b_flat,
    output reg  signed [31:0] y
);
```

`a_flat` and `b_flat` each pack eight signed 8-bit values, **little-endian by
element**: element `i` occupies bits `[8*i+7 : 8*i]`, so element 0 is the least
significant byte.

Behavior on the rising edge of `clk`:

- If `rst` is high, `y` becomes 0. Reset takes priority over `en`.
- Else if `en` is high, `y` becomes the sum of the eight signed products
  `a[i] * b[i]` for i = 0..7, computed from that cycle's inputs.
- Else `y` holds.

`y` is **not** an accumulator. Each enabled cycle replaces it with a fresh dot
product. The eight multiplies must be signed; unpacking the bytes as unsigned is
the failure mode to avoid.
