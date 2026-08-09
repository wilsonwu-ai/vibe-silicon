-- Known-good reference implementation. Used only to prove tb.vhdl accepts
-- correct work. The model under test never sees this file.
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
    begin
        if rising_edge(clk) then
            if rst = '1' then
                acc_r <= (others => '0');
            elsif en = '1' then
                acc_r <= acc_r + resize(a * b, 32);
            end if;
        end if;
    end process;

    acc <= acc_r;
end architecture rtl;
