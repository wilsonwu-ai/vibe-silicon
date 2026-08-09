-- Hand-written. The model under test never sees this file.
-- Mirrors tb.v vector for vector: same stimulus, same order, same expectations.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb is
end entity tb;

architecture sim of tb is

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal in_valid  : std_logic := '0';
  signal in_ready  : std_logic;
  signal a         : signed(7 downto 0) := (others => '0');
  signal b         : signed(7 downto 0) := (others => '0');
  signal out_valid : std_logic;
  signal out_ready : std_logic := '0';
  signal y         : signed(31 downto 0);

  signal running : boolean := true;

  procedure print(s : in string) is
    variable l : line;
  begin
    write(l, s);
    writeline(output, l);
  end procedure print;

  function img(v : in signed) return string is
  begin
    if is_x(std_ulogic_vector(v)) then
      return "X";
    else
      return integer'image(to_integer(v));
    end if;
  end function img;

  function bimg(v : in std_logic) return string is
  begin
    return std_logic'image(v);
  end function bimg;

begin

  dut : entity work.vr_mac
    port map (clk       => clk,
              rst       => rst,
              in_valid  => in_valid,
              in_ready  => in_ready,
              a         => a,
              b         => b,
              out_valid => out_valid,
              out_ready => out_ready,
              y         => y);

  clk_gen : process
  begin
    while running loop
      wait for 5 ns;
      clk <= not clk;
    end loop;
    wait;
  end process clk_gen;

  stim : process
    variable errors    : integer := 0;
    variable exp_total : integer := 0;

    -- Drive one operand pair for the cycle leading into the accept edge,
    -- then release in_valid. Assumes in_ready is already '1' (idle).
    procedure send(ai : integer; bi : integer) is
    begin
      a <= to_signed(ai, 8); b <= to_signed(bi, 8); in_valid <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      in_valid <= '0';
      if in_ready /= '0' then
        print("FAIL: in_ready did not drop the cycle after an accepted transfer");
        errors := errors + 1;
      end if;
    end procedure send;
  begin
    rst <= '1'; out_ready <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    if in_ready /= '1' or out_valid /= '0' or y /= to_signed(0, 32) then
      print("FAIL reset: in_ready=" & bimg(in_ready) & " out_valid=" & bimg(out_valid) &
            " y=" & img(y));
      errors := errors + 1;
    end if;
    rst <= '0';

    -- --- transaction 1: no backpressure, out_ready held high throughout ---
    out_ready <= '1';
    if in_ready /= '1' then
      print("FAIL: not idle/ready before transaction 1");
      errors := errors + 1;
    end if;
    send(5, 6);                              -- accept edge; a*b = 30
    exp_total := 30;

    wait until rising_edge(clk);
    wait for 1 ns;                           -- MULT cycle -- no result yet
    if out_valid /= '0' then
      print("FAIL: out_valid asserted too early (after MULT cycle only): out_valid=" & bimg(out_valid));
      errors := errors + 1;
    end if;

    wait until rising_edge(clk);
    wait for 1 ns;                           -- ACCUM -> DONE, result now visible
    if out_valid /= '1' or y /= to_signed(exp_total, 32) then
      print("FAIL transaction 1: out_valid=" & bimg(out_valid) & " y=" & img(y) &
            " expected out_valid=1 y=" & integer'image(exp_total));
      errors := errors + 1;
    end if;

    -- out_ready was already '1', so this same edge completes the handshake
    wait until rising_edge(clk);
    wait for 1 ns;
    if in_ready /= '1' or out_valid /= '0' then
      print("FAIL: did not return to idle after out_ready handshake: in_ready=" & bimg(in_ready) &
            " out_valid=" & bimg(out_valid));
      errors := errors + 1;
    end if;

    -- --- transaction 2: running total carries across transactions ---
    send(-4, 9);                             -- a*b = -36, running total 30-36=-6
    exp_total := exp_total + (-4 * 9);
    wait until rising_edge(clk); wait for 1 ns;    -- MULT
    wait until rising_edge(clk); wait for 1 ns;    -- ACCUM -> DONE, result visible
    if out_valid /= '1' or y /= to_signed(exp_total, 32) then
      print("FAIL transaction 2 (accumulation): out_valid=" & bimg(out_valid) & " y=" & img(y) &
            " expected=" & integer'image(exp_total));
      errors := errors + 1;
    end if;
    wait until rising_edge(clk); wait for 1 ns;    -- handshake completes, back to idle

    -- --- transaction 3: backpressure -- out_ready held low, result must hold ---
    out_ready <= '0';
    send(10, 10);                            -- a*b = 100
    exp_total := exp_total + (10 * 10);
    wait until rising_edge(clk); wait for 1 ns;    -- MULT
    wait until rising_edge(clk); wait for 1 ns;    -- ACCUM -> DONE, result visible, out_ready='0'
    if out_valid /= '1' or y /= to_signed(exp_total, 32) then
      print("FAIL transaction 3 pre-stall: out_valid=" & bimg(out_valid) & " y=" & img(y) &
            " expected=" & integer'image(exp_total));
      errors := errors + 1;
    end if;

    -- stall for several cycles: result and out_valid must not move, and a
    -- new input transfer must be ignored while busy (in_ready stays '0')
    a <= to_signed(99, 8); b <= to_signed(99, 8); in_valid <= '1';  -- try to sneak in a new transfer
    for i in 0 to 2 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      if out_valid /= '1' or y /= to_signed(exp_total, 32) then
        print("FAIL: result changed or dropped during backpressure stall: out_valid=" &
              bimg(out_valid) & " y=" & img(y) & " expected=" & integer'image(exp_total));
        errors := errors + 1;
      end if;
      if in_ready /= '0' then
        print("FAIL: in_ready went high while a result was still waiting to be collected");
        errors := errors + 1;
      end if;
    end loop;
    in_valid <= '0';

    -- release backpressure
    out_ready <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    if in_ready /= '1' or out_valid /= '0' then
      print("FAIL: did not return to idle once out_ready went high: in_ready=" & bimg(in_ready) &
            " out_valid=" & bimg(out_valid));
      errors := errors + 1;
    end if;

    -- --- mid-transaction reset takes priority over everything ---
    send(20, 20);
    wait until rising_edge(clk);
    wait for 1 ns;                           -- now mid-computation (MULT)
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    if in_ready /= '1' or out_valid /= '0' or y /= to_signed(0, 32) then
      print("FAIL: reset mid-transaction did not return to power-on state: in_ready=" &
            bimg(in_ready) & " out_valid=" & bimg(out_valid) & " y=" & img(y));
      errors := errors + 1;
    end if;
    rst <= '0';

    if errors = 0 then
      print("ALL TESTS PASSED");
    else
      print("TESTS FAILED: " & integer'image(errors));
    end if;

    running <= false;
    finish;
  end process stim;

  watchdog : process
  begin
    wait for 20000 ns;
    print("TESTS FAILED: timeout");
    finish;
  end process watchdog;

end architecture sim;
