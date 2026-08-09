Write a purely combinational 4-element signed 8-bit dot product.

```
module dot4_int8 (
    input  wire signed [7:0]  a0, a1, a2, a3,
    input  wire signed [7:0]  b0, b1, b2, b3,
    output wire signed [19:0] y
);
```

`y` is `a0*b0 + a1*b1 + a2*b2 + a3*b3`, computed in signed arithmetic.

No clock, no registers, no state. 20 bits is exactly wide enough for the worst
case (4 x 127 x 127 = 64516), so no saturation or clamping is needed.
