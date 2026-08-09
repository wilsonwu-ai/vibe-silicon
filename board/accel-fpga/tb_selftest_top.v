`timescale 1ns/1ps
// Sim-only sanity check for accel_selftest_top.v, before spending a Quartus
// run on it. Not part of bench/'s CONTRACT.md apparatus -- just confirms the
// wrapper wires up correctly and every one of the 10 checks (same vectors as
// bench/tasks/mac_array8/tb.v) actually lands on PASS before synthesizing.
// Reaches into the DUT hierarchy directly (fine in simulation) rather than
// pattern-matching LEDR, so a wiring mistake in the LED-display mux can't
// mask a real failure.
module tb_selftest_top;
  reg clk = 0;
  reg key0 = 1;   // idle high, active-low
  wire [9:0] ledr;

  // TICK_MAX small enough that the whole 10-step run finishes in a few
  // thousand ns instead of ~2.5 real-time seconds at 50 MHz.
  accel_selftest_top #(.TICK_MAX(26'd3)) dut (
    .CLOCK_50 (clk),
    .KEY0     (key0),
    .LEDR     (ledr)
  );

  always #10 clk = ~clk;   // 20ns period, shape only -- TICK_MAX makes the rate irrelevant

  integer errors = 0;

  task wait_for_done;
    integer guard;
    begin
      guard = 0;
      while (dut.step != 4'd10 && guard < 1000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (dut.step != 4'd10) begin
        $display("FAIL: sequencer never reached done (step=%0d)", dut.step);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    wait_for_done;
    if (dut.fail_latch) begin
      $display("FAIL: self-test reported a mismatch (fail_latch=1) -- check per-step vectors/expected values");
      errors = errors + 1;
    end else begin
      $display("first run: all 10 checks matched, LEDR=%b (expect all-1)", ledr);
      if (ledr !== 10'b11_1111_1111) begin
        $display("FAIL: fail_latch clear but LEDR display isn't steady-on: %b", ledr);
        errors = errors + 1;
      end
    end

    // exercise KEY0: hold it low like a real button press (long enough for
    // the 2-FF synchronizer to see it), release, and confirm the sequencer
    // re-arms to step 0 before running the whole sequence again.
    key0 = 0;
    repeat (5) @(posedge clk);
    key0 = 1;
    repeat (3) @(posedge clk);
    if (dut.step > 4'd2) begin
      $display("FAIL: KEY0 did not re-arm the sequencer (step=%0d, expected close to 0)", dut.step);
      errors = errors + 1;
    end

    wait_for_done;
    if (dut.fail_latch) begin
      $display("FAIL: second run (after KEY0 restart) reported a mismatch");
      errors = errors + 1;
    end else begin
      $display("second run (post-restart): all 10 checks matched again, LEDR=%b", ledr);
    end

    if (errors == 0) $display("ALL TESTS PASSED");
    else              $display("TESTS FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #100000;
    $display("TESTS FAILED: timeout");
    $finish;
  end
endmodule
