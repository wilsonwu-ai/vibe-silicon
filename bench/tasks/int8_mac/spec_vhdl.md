Write a signed 8-bit multiply-accumulate unit.

```
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity int8_mac is
    port (
        clk : in  std_logic;
        rst : in  std_logic;   -- synchronous, active high
        en  : in  std_logic;
        a   : in  signed(7 downto 0);
        b   : in  signed(7 downto 0);
        acc : out signed(31 downto 0)
    );
end entity int8_mac;
```

Behavior, all on the rising edge of `clk`:

- If `rst` is high, `acc` becomes 0. Reset takes priority over `en`.
- Else if `en` is high, `acc` becomes `acc + (a * b)`.
- Else `acc` holds its current value.

The product `a * b` must be a signed multiply. Accumulation is in 32-bit signed
arithmetic and is allowed to wrap.
