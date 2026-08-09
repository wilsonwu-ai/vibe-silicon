-- Deliberately WRONG. Failure mode: signedness -- the signed inputs are cast to
-- unsigned before multiplying, so negative operands become large positives.
-- Compiles and elaborates cleanly; only the testbench catches it.
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
    signal p0, p1, p2, p3 : unsigned(15 downto 0);
    signal sum            : unsigned(19 downto 0);
begin
    p0 <= unsigned(a0) * unsigned(b0);
    p1 <= unsigned(a1) * unsigned(b1);
    p2 <= unsigned(a2) * unsigned(b2);
    p3 <= unsigned(a3) * unsigned(b3);

    sum <= resize(p0, 20) + resize(p1, 20) + resize(p2, 20) + resize(p3, 20);

    y <= signed(sum);
end architecture rtl;
