-- ADVERSARIAL PROBE (not part of the frozen bench).
-- Failure mode: incomplete sensitivity list on a combinational process -- the
-- VHDL cousin of latch inference. The b* operands are missing, so the process
-- does not re-evaluate when they change. Analyses and elaborates clean.
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
begin
    process (a0, a1, a2, a3)            -- BUG: b0..b3 missing
    begin
        y <= resize(a0*b0, 20) + resize(a1*b1, 20)
           + resize(a2*b2, 20) + resize(a3*b3, 20);
    end process;
end architecture rtl;
