-- Deliberately WRONG. Failure mode: signal vs variable assignment in the clocked
-- process (the VHDL cognate of blocking vs non-blocking). `sum` is meant to be a
-- same-cycle temporary but is a signal, so its update is not visible until the
-- next cycle and `y` registers the PREVIOUS cycle's dot product. Analyses and
-- elaborates cleanly; only the testbench catches it.
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
    signal sum : signed(31 downto 0);   -- BUG: should be a process variable
begin

    process (clk)
        variable prods : signed(31 downto 0);
        variable prod  : signed(15 downto 0);
    begin
        if rising_edge(clk) then
            prods := (others => '0');
            for i in 0 to 7 loop
                prod  := signed(a_flat(8*i + 7 downto 8*i))
                       * signed(b_flat(8*i + 7 downto 8*i));
                prods := prods + resize(prod, 32);
            end loop;

            sum <= prods;               -- signal update lands next cycle

            if rst = '1' then
                y <= (others => '0');
            elsif en = '1' then
                y <= sum;               -- reads last cycle's value, not this one's
            end if;
        end if;
    end process;

end architecture rtl;
