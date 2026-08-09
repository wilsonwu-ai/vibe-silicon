-- Known-good implementation. Exists only to prove tb.vhdl accepts good work.
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
    signal p0, p1, p2, p3 : signed(15 downto 0);
begin
    p0 <= a0 * b0;
    p1 <= a1 * b1;
    p2 <= a2 * b2;
    p3 <= a3 * b3;

    y <= resize(p0, 20) + resize(p1, 20) + resize(p2, 20) + resize(p3, 20);
end architecture rtl;
