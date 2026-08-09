-- Deliberately WRONG. Failure mode: ignores backpressure. `out_valid` is
-- asserted for exactly one cycle and the unit returns to idle unconditionally
-- regardless of `out_ready`, so a stalled downstream (out_ready held low)
-- silently loses the result instead of the unit holding it. Analyses and
-- elaborates cleanly; only a backpressure test catches it.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vr_mac is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        in_valid  : in  std_logic;
        in_ready  : out std_logic;
        a         : in  signed(7 downto 0);
        b         : in  signed(7 downto 0);
        out_valid : out std_logic;
        out_ready : in  std_logic;
        y         : out signed(31 downto 0)
    );
end entity vr_mac;

architecture rtl of vr_mac is
    type state_t is (S_IDLE, S_MULT, S_ACCUM, S_DONE);
    signal state : state_t := S_IDLE;
    signal a_lat, b_lat : signed(7 downto 0)  := (others => '0');
    signal prod         : signed(15 downto 0) := (others => '0');
    signal acc          : signed(31 downto 0) := (others => '0');
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= S_IDLE;
                in_ready  <= '1';
                out_valid <= '0';
                acc       <= (others => '0');
                y         <= (others => '0');
                a_lat     <= (others => '0');
                b_lat     <= (others => '0');
                prod      <= (others => '0');
            else
                case state is
                    when S_IDLE =>
                        in_ready  <= '1';
                        out_valid <= '0';
                        if in_valid = '1' then
                            a_lat    <= a;
                            b_lat    <= b;
                            in_ready <= '0';
                            state    <= S_MULT;
                        end if;

                    when S_MULT =>
                        in_ready <= '0';
                        prod     <= a_lat * b_lat;
                        state    <= S_ACCUM;

                    when S_ACCUM =>
                        in_ready  <= '0';
                        acc       <= acc + resize(prod, 32);
                        y         <= acc + resize(prod, 32);
                        out_valid <= '1';
                        state     <= S_DONE;

                    when S_DONE =>
                        -- BUG: unconditionally drops out_valid and returns to
                        -- idle, ignoring out_ready.
                        in_ready  <= '1';
                        out_valid <= '0';
                        state     <= S_IDLE;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;
