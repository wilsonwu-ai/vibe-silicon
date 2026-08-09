-- ADVERSARIAL PROBE (not part of the frozen bench).
-- Failure mode: wrong bit width truncating the product. The a*b result is 16
-- bits wide but is sliced down to 8 before being accumulated, so every product
-- larger than +-127 is silently truncated. Analyses and elaborates clean.
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

architecture rtl of int8_mac is
    signal acc_r : signed(31 downto 0);
begin
    process (clk)
        variable p16  : signed(15 downto 0);
        variable prod : signed(7 downto 0);
    begin
        if rising_edge(clk) then
            p16  := a * b;
            prod := p16(7 downto 0);        -- BUG: 8 bits, should be 16
            if rst = '1' then
                acc_r <= (others => '0');
            elsif en = '1' then
                acc_r <= acc_r + resize(prod, 32);
            end if;
        end if;
    end process;

    acc <= acc_r;
end architecture rtl;
