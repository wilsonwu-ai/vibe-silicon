-- Known-good reference implementation. Exists only to prove tb.vhdl accepts
-- correct work. The model under test never sees this file.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vr_mac is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;  -- synchronous, active high
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
                        in_ready  <= '0';
                        out_valid <= '1';
                        if out_ready = '1' then
                            out_valid <= '0';
                            in_ready  <= '1';
                            state     <= S_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;
