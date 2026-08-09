-- Known-good reference. Exists only to prove tb.vhdl accepts correct work.
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

architecture rtl of mac_array8 is
begin

    process (clk)
        variable acc  : signed(31 downto 0);
        variable prod : signed(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                y <= (others => '0');
            elsif en = '1' then
                acc := (others => '0');
                for i in 0 to 7 loop
                    prod := signed(a_flat(8*i + 7 downto 8*i))
                          * signed(b_flat(8*i + 7 downto 8*i));
                    acc := acc + resize(prod, 32);
                end loop;
                y <= acc;
            end if;
        end if;
    end process;

end architecture rtl;
