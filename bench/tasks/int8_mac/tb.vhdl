-- Hand-written. The model under test never sees this file.
-- Mirrors tb.v vector for vector: same stimulus, same order, same expectations.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.finish;

entity tb is
end entity tb;

architecture sim of tb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal en  : std_logic := '0';
  signal a   : signed(7 downto 0) := (others => '0');
  signal b   : signed(7 downto 0) := (others => '0');
  signal acc : signed(31 downto 0);

  signal running : boolean := true;

  type vec_t is array (0 to 8) of signed(7 downto 0);
  -- steps 6-8 add three more +127*127 (=16129) products, pushing the running
  -- total past 32767 (the 16-bit signed range) -- catches an internal
  -- accumulator narrower than the 32-bit port and just sign-extended out
  constant va : vec_t := (to_signed(   3, 8), to_signed(  -5, 8),
                          to_signed( 127, 8), to_signed(-127, 8),
                          to_signed(   0, 8), to_signed(  -1, 8),
                          to_signed( 127, 8), to_signed( 127, 8),
                          to_signed( 127, 8));
  constant vb : vec_t := (to_signed(   4, 8), to_signed(   7, 8),
                          to_signed( 127, 8), to_signed( 127, 8),
                          to_signed(  99, 8), to_signed(  -1, 8),
                          to_signed( 127, 8), to_signed( 127, 8),
                          to_signed( 127, 8));

  procedure print(s : string) is
    variable l : line;
  begin
    write(l, s);
    writeline(output, l);
  end procedure print;

  -- Decimal when the value is fully defined, bit string otherwise, so that a
  -- DUT leaving the output at 'U'/'X' is reported rather than silently coerced.
  function img(v : signed) return string is
  begin
    for i in v'range loop
      if v(i) /= '0' and v(i) /= '1' then
        return to_string(std_logic_vector(v));
      end if;
    end loop;
    return integer'image(to_integer(v));
  end function img;

begin

  dut : entity work.int8_mac
    port map (clk => clk, rst => rst, en => en, a => a, b => b, acc => acc);

  clk_gen : process
  begin
    while running loop
      wait for 5 ns;
      clk <= not clk;
    end loop;
    wait;
  end process clk_gen;

  stim : process
    variable errors  : integer := 0;
    variable exp_acc : integer := 0;
  begin
    rst <= '1'; en <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    if acc /= to_signed(0, 32) then
      print("FAIL reset: acc=" & img(acc) & " expected 0");
      errors := errors + 1;
    end if;

    rst <= '0';
    exp_acc := 0;
    for i in 0 to 8 loop
      a <= va(i); b <= vb(i); en <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      exp_acc := exp_acc + (to_integer(va(i)) * to_integer(vb(i)));
      if acc /= to_signed(exp_acc, 32) then
        print("FAIL step " & integer'image(i) &
              " (a=" & integer'image(to_integer(va(i))) &
              " b=" & integer'image(to_integer(vb(i))) & "): acc=" & img(acc) &
              " expected=" & integer'image(exp_acc));
        errors := errors + 1;
      end if;
    end loop;

    -- en low must hold, not accumulate
    en <= '0'; a <= to_signed(50, 8); b <= to_signed(50, 8);
    wait until rising_edge(clk);
    wait for 1 ns;
    if acc /= to_signed(exp_acc, 32) then
      print("FAIL hold with en=0: acc=" & img(acc) &
            " expected=" & integer'image(exp_acc));
      errors := errors + 1;
    end if;

    -- mid-cycle reset: assert rst strictly between clock edges (not aligned
    -- to a rising_edge wait), which a synchronous design must NOT react to
    -- until the following rising edge -- catches an async reset
    en <= '1'; a <= to_signed(5, 8); b <= to_signed(5, 8);
    wait until rising_edge(clk);
    wait for 1 ns;
    exp_acc := exp_acc + (5 * 5);
    if acc /= to_signed(exp_acc, 32) then
      print("FAIL pre-midrst: acc=" & img(acc) & " expected=" & integer'image(exp_acc));
      errors := errors + 1;
    end if;
    wait for 1 ns;
    rst <= '1';              -- assert well inside the current clock period
    wait for 1 ns;
    if acc /= to_signed(exp_acc, 32) then
      print("FAIL rst reacted before the next clock edge (looks async): acc=" & img(acc) &
            " expected=" & integer'image(exp_acc) & " (unchanged)");
      errors := errors + 1;
    end if;
    wait until rising_edge(clk);
    wait for 1 ns;
    if acc /= to_signed(0, 32) then
      print("FAIL sync reset did not take effect at the next posedge: acc=" & img(acc) & " expected 0");
      errors := errors + 1;
    end if;
    rst <= '0'; en <= '0';

    -- reset must win over en
    rst <= '1'; en <= '1'; a <= to_signed(9, 8); b <= to_signed(9, 8);
    wait until rising_edge(clk);
    wait for 1 ns;
    if acc /= to_signed(0, 32) then
      print("FAIL reset priority over en: acc=" & img(acc) & " expected 0");
      errors := errors + 1;
    end if;

    if errors = 0 then print("ALL TESTS PASSED");
    else                print("TESTS FAILED: " & integer'image(errors));
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
