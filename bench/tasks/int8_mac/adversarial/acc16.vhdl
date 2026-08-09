library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity int8_mac is port (clk,rst,en : in std_logic;
  a,b : in signed(7 downto 0); acc : out signed(31 downto 0));
end entity int8_mac;
architecture rtl of int8_mac is signal r : signed(15 downto 0);
begin process(clk) begin if rising_edge(clk) then
  if rst='1' then r <= (others=>'0'); elsif en='1' then r <= r + resize(a*b,16); end if;
 end if; end process; acc <= resize(r,32); end architecture rtl;
