-- Hand-written. The model under test never sees this file.
-- Mirrors tb.v exactly: same stimulus, same order, same expected results.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb is
end entity tb;

architecture sim of tb is
    signal a0, a1, a2, a3 : signed(7 downto 0)  := (others => '0');
    signal b0, b1, b2, b3 : signed(7 downto 0)  := (others => '0');
    signal y              : signed(19 downto 0);
begin

    dut : entity work.dot4_int8
        port map (
            a0 => a0, a1 => a1, a2 => a2, a3 => a3,
            b0 => b0, b1 => b1, b2 => b2, b3 => b3,
            y  => y
        );

    stim : process
        variable errors : integer := 0;
        variable exp    : integer;
        variable l      : line;

        procedure apply(p0, p1, p2, p3 : integer;
                        q0, q1, q2, q3 : integer) is
        begin
            a0 <= to_signed(p0, 8);
            a1 <= to_signed(p1, 8);
            a2 <= to_signed(p2, 8);
            a3 <= to_signed(p3, 8);
            b0 <= to_signed(q0, 8);
            b1 <= to_signed(q1, 8);
            b2 <= to_signed(q2, 8);
            b3 <= to_signed(q3, 8);
            exp := p0*q0 + p1*q1 + p2*q2 + p3*q3;
            wait for 1 ns;
            if is_x(std_logic_vector(y)) then
                write(l, string'("FAIL: got X expected ")
                       & integer'image(exp));
                writeline(output, l);
                errors := errors + 1;
            elsif to_integer(y) /= exp then
                write(l, string'("FAIL: got ")
                       & integer'image(to_integer(y))
                       & string'(" expected ") & integer'image(exp));
                writeline(output, l);
                errors := errors + 1;
            end if;
        end procedure apply;

    begin
        apply(   1,   2,   3,   4,     5,   6,   7,   8);
        apply(  -1,  -2,  -3,  -4,     5,   6,   7,   8);
        apply( 127, 127, 127, 127,   127, 127, 127, 127);
        apply(-127, 127,-127, 127,   127, 127, 127, 127);
        apply(   0,   0,   0,   0,    42,  42,  42,  42);
        apply(-100,  50, -25,  12,     3,  -4,   5,  -6);
        apply(   1,   0,   0,   0,    -1,   0,   0,   0);

        -- a0=0 immediately follows a step with a *different* expected
        -- result, so a latch retaining the previous y (an incomplete `if`
        -- with no `else`) cannot coincidentally still match.
        apply(   9,   9,   9,   9,     1,   1,   1,   1);   -- exp 36
        apply(   0,   5,   5,   5,     3,   3,   3,   3);   -- exp 45

        -- identical a-operands, only b changes -- catches a process
        -- sensitivity list missing the b* signals.
        apply(   3,   1,   4,   1,     2,   7,   1,   8);   -- exp 25
        apply(   3,   1,   4,   1,     5,   9,   2,   6);   -- exp 38

        if errors = 0 then
            write(l, string'("ALL TESTS PASSED"));
        else
            write(l, string'("TESTS FAILED: ") & integer'image(errors));
        end if;
        writeline(output, l);
        finish;
        wait;
    end process stim;

    watchdog : process
        variable l : line;
    begin
        wait for 20 us;
        write(l, string'("TESTS FAILED: timeout"));
        writeline(output, l);
        finish;
        wait;
    end process watchdog;

end architecture sim;
