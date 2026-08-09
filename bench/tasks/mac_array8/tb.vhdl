-- Hand-written. The model under test never sees this file.
-- Mirrors tb.v vector-for-vector: same stimulus, same order, same expectations.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb is
end entity tb;

architecture sim of tb is

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal en     : std_logic := '0';
  signal a_flat : std_logic_vector(63 downto 0) := (others => '0');
  signal b_flat : std_logic_vector(63 downto 0) := (others => '0');
  signal y      : signed(31 downto 0);

  signal running : boolean := true;

  type int8_array is array (0 to 7) of signed(7 downto 0);

  procedure print(s : in string) is
    variable l : line;
  begin
    write(l, s);
    writeline(output, l);
  end procedure print;

  -- Decimal image of y, metavalue-safe (mirrors %0d on a 4-state value).
  function img(v : in signed) return string is
  begin
    if is_x(std_ulogic_vector(v)) then
      return "X";
    else
      return integer'image(to_integer(v));
    end if;
  end function img;

begin

  dut : entity work.mac_array8
    port map (clk    => clk,
              rst    => rst,
              en     => en,
              a_flat => a_flat,
              b_flat => b_flat,
              y      => y);

  clk_gen : process
  begin
    while running loop
      wait for 5 ns;
      clk <= not clk;
    end loop;
    wait;
  end process clk_gen;

  stim : process
    variable av     : int8_array;
    variable bv     : int8_array;
    variable exp    : integer;
    variable errors : integer := 0;

    procedure load is  -- pack the arrays and compute the expected value
    begin
      exp := 0;
      for k in 0 to 7 loop
        a_flat(8*k + 7 downto 8*k) <= std_logic_vector(av(k));
        b_flat(8*k + 7 downto 8*k) <= std_logic_vector(bv(k));
        exp := exp + to_integer(av(k)) * to_integer(bv(k));
      end loop;
    end procedure load;
  begin
    rst <= '1'; en <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(0, 32) then
      print("FAIL reset: y=" & img(y) & " expected 0");
      errors := errors + 1;
    end if;
    rst <= '0';

    -- case 1: ascending against a constant
    for i in 0 to 7 loop
      av(i) := to_signed(i + 1, 8);
      bv(i) := to_signed(2, 8);
    end loop;
    load; en <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(exp, 32) then
      print("FAIL case1: y=" & img(y) & " expected=" & integer'image(exp));
      errors := errors + 1;
    end if;

    -- case 2: negative a, positive b (catches unsigned unpacking)
    for i in 0 to 7 loop
      av(i) := to_signed(-(i + 1), 8);
      bv(i) := to_signed(3, 8);
    end loop;
    load;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(exp, 32) then
      print("FAIL case2 (signedness): y=" & img(y) & " expected=" & integer'image(exp));
      errors := errors + 1;
    end if;

    -- case 3: both negative, must come out positive
    for i in 0 to 7 loop
      av(i) := to_signed(-127, 8);
      bv(i) := to_signed(-127, 8);
    end loop;
    load;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(exp, 32) then
      print("FAIL case3: y=" & img(y) & " expected=" & integer'image(exp));
      errors := errors + 1;
    end if;

    -- case 4: mixed signs must cancel to exactly zero
    for i in 0 to 7 loop
      if (i mod 2) = 0 then
        av(i) := to_signed(100, 8);
      else
        av(i) := to_signed(-100, 8);
      end if;
      bv(i) := to_signed(50, 8);
    end loop;
    load;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(exp, 32) or y /= to_signed(0, 32) then
      print("FAIL case4: y=" & img(y) & " expected=" & integer'image(exp) & " (0)");
      errors := errors + 1;
    end if;

    -- case 5: replaces, does not accumulate
    for i in 0 to 7 loop
      av(i) := to_signed(1, 8);
      bv(i) := to_signed(1, 8);
    end loop;
    load;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(8, 32) then
      print("FAIL case5 (accumulated instead of replaced): y=" & img(y) & " expected 8");
      errors := errors + 1;
    end if;

    -- case 6: byte-order sensitive -- both operands vary independently per
    -- lane, so a big-endian element unpacking changes the sum
    for i in 0 to 7 loop
      av(i) := to_signed(i + 1, 8);
      bv(i) := to_signed(8 - i, 8);
    end loop;
    load;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(exp, 32) then
      print("FAIL case6 (byte order): y=" & img(y) & " expected=" & integer'image(exp));
      errors := errors + 1;
    end if;

    -- case 7: partial-sum magnitude exceeds 16 bits (8 * 127*127 = 129032),
    -- catches a truncated internal accumulator sign-extended to the port
    for i in 0 to 7 loop
      av(i) := to_signed(127, 8);
      bv(i) := to_signed(127, 8);
    end loop;
    load;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(exp, 32) then
      print("FAIL case7 (>16-bit sum): y=" & img(y) & " expected=" & integer'image(exp));
      errors := errors + 1;
    end if;

    -- mid-cycle reset: assert rst strictly between clock edges (not aligned
    -- to a rising_edge wait), which a synchronous design must NOT react to
    -- until the following rising edge -- catches an async reset
    for i in 0 to 7 loop
      av(i) := to_signed(5, 8);
      bv(i) := to_signed(5, 8);
    end loop;
    load; en <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(exp, 32) then
      print("FAIL pre-midrst: y=" & img(y) & " expected=" & integer'image(exp));
      errors := errors + 1;
    end if;
    wait for 1 ns;
    rst <= '1';              -- assert well inside the current clock period
    wait for 1 ns;
    if y /= to_signed(exp, 32) then
      print("FAIL rst reacted before the next clock edge (looks async): y=" & img(y) & " expected=" & integer'image(exp) & " (unchanged)");
      errors := errors + 1;
    end if;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(0, 32) then
      print("FAIL sync reset did not take effect at the next posedge: y=" & img(y) & " expected 0");
      errors := errors + 1;
    end if;
    rst <= '0'; en <= '0';

    -- en low holds
    en <= '0';
    for i in 0 to 7 loop
      av(i) := to_signed(9, 8);
      bv(i) := to_signed(9, 8);
    end loop;
    load;
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(0, 32) then
      print("FAIL hold with en=0: y=" & img(y) & " expected 0");
      errors := errors + 1;
    end if;

    -- reset beats en
    rst <= '1'; en <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    if y /= to_signed(0, 32) then
      print("FAIL reset priority over en: y=" & img(y) & " expected 0");
      errors := errors + 1;
    end if;

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
