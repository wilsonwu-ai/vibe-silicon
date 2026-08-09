-- ADVERSARIAL PROBE (not part of the frozen bench).
-- Failure mode: wrong intermediate width, the canonical numeric_std trap. In
-- numeric_std the result of "+" is as wide as its widest operand, so summing
-- the 16-bit products without resizing first wraps at 16 bits before the sum
-- is widened to the 20-bit output. Analyses and elaborates clean.
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

architecture rtl of dot4_int8 is
    -- BUG: 16 bits cannot hold 4 x 127 x 127 = 64516
    signal s : signed(15 downto 0);
begin
    s <= a0*b0 + a1*b1 + a2*b2 + a3*b3;

    y <= resize(s, 20);
end architecture rtl;
