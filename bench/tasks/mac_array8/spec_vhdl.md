Write an 8-wide signed 8-bit dot product with a registered output. This is the
core of the GEMV accelerator, so it must map onto DSP blocks.

```
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_array8 is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;  -- synchronous, active high
        en     : in  std_logic;
        a_flat : in  std_logic_vector(63 downto 0);
        b_flat : in  std_logic_vector(63 downto 0);
        y      : out signed(31 downto 0)
    );
end entity mac_array8;
```

`a_flat` and `b_flat` each pack eight signed 8-bit values, **little-endian by
element**: element `i` occupies bits `8*i+7 downto 8*i`, so element 0 is the
least significant byte.

Behavior on the rising edge of `clk`:

- If `rst` is high, `y` becomes 0. Reset takes priority over `en`.
- Else if `en` is high, `y` becomes the sum of the eight signed products
  `a(i) * b(i)` for i = 0..7, computed from that cycle's inputs.
- Else `y` holds.

`y` is **not** an accumulator. Each enabled cycle replaces it with a fresh dot
product.
