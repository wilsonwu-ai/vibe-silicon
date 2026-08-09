Write a purely combinational 4-element signed 8-bit dot product.

```
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dot4_int8 is
    port (
        a0, a1, a2, a3 : in  signed(7 downto 0);
        b0, b1, b2, b3 : in  signed(7 downto 0);
        y              : out signed(19 downto 0)
    );
end entity dot4_int8;
```

`y` is `a0*b0 + a1*b1 + a2*b2 + a3*b3`, computed in signed arithmetic.

No clock, no registers, no state. 20 bits is exactly wide enough for the worst
case (4 x 127 x 127 = 64516), so no saturation or clamping is needed.
