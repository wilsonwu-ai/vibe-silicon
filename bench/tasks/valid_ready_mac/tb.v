`timescale 1ns/1ps
// Hand-written. The model under test never sees this file.
module tb;
  reg clk = 0;
  reg rst = 1;
  reg in_valid = 0;
  wire in_ready;
  reg signed [7:0] a = 0;
  reg signed [7:0] b = 0;
  wire out_valid;
  reg out_ready = 0;
  wire signed [31:0] y;

  integer errors = 0;
  integer exp_total;

  vr_mac dut (.clk(clk), .rst(rst), .in_valid(in_valid), .in_ready(in_ready),
              .a(a), .b(b), .out_valid(out_valid), .out_ready(out_ready), .y(y));

  always #5 clk = ~clk;

  // Drive one operand pair for the cycle leading into the accept edge, then
  // release in_valid. Assumes in_ready is already high (idle) -- callers
  // check that themselves so a false accept doesn't hide as a silent no-op.
  task send;
    input signed [7:0] ai;
    input signed [7:0] bi;
    begin
      a = ai; b = bi; in_valid = 1;
      @(posedge clk); #1;
      in_valid = 0;
      if (in_ready !== 1'b0) begin
        $display("FAIL: in_ready did not drop the cycle after an accepted transfer");
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    rst = 1; out_ready = 0;
    @(posedge clk); #1;
    if (in_ready !== 1'b1 || out_valid !== 1'b0 || y !== 0) begin
      $display("FAIL reset: in_ready=%0d out_valid=%0d y=%0d", in_ready, out_valid, y);
      errors = errors + 1;
    end
    rst = 0;

    // --- transaction 1: no backpressure, out_ready held high throughout ---
    out_ready = 1;
    if (in_ready !== 1'b1) begin
      $display("FAIL: not idle/ready before transaction 1");
      errors = errors + 1;
    end
    send(8'sd5, 8'sd6);                    // accept edge; a*b = 30
    exp_total = 30;

    @(posedge clk); #1;                    // MULT cycle -- no result yet
    if (out_valid !== 1'b0) begin
      $display("FAIL: out_valid asserted too early (after MULT cycle only): out_valid=%0d", out_valid);
      errors = errors + 1;
    end

    @(posedge clk); #1;                    // ACCUM -> DONE, result now visible
    if (out_valid !== 1'b1 || y !== exp_total) begin
      $display("FAIL transaction 1: out_valid=%0d y=%0d expected out_valid=1 y=%0d",
                out_valid, y, exp_total);
      errors = errors + 1;
    end

    // out_ready was already high, so this same edge completes the handshake
    @(posedge clk); #1;
    if (in_ready !== 1'b1 || out_valid !== 1'b0) begin
      $display("FAIL: did not return to idle after out_ready handshake: in_ready=%0d out_valid=%0d",
                in_ready, out_valid);
      errors = errors + 1;
    end

    // --- transaction 2: running total carries across transactions ---
    send(-8'sd4, 8'sd9);                   // a*b = -36, running total 30-36=-6
    exp_total = exp_total + (-4 * 9);
    @(posedge clk); #1;                    // MULT
    @(posedge clk); #1;                    // ACCUM -> DONE, result visible
    if (out_valid !== 1'b1 || y !== exp_total) begin
      $display("FAIL transaction 2 (accumulation): out_valid=%0d y=%0d expected=%0d",
                out_valid, y, exp_total);
      errors = errors + 1;
    end
    @(posedge clk); #1;                    // handshake completes, back to idle

    // --- transaction 3: backpressure -- out_ready held low, result must hold ---
    out_ready = 0;
    send(8'sd10, 8'sd10);                  // a*b = 100
    exp_total = exp_total + (10 * 10);
    @(posedge clk); #1;                    // MULT
    @(posedge clk); #1;                    // ACCUM -> DONE, result visible, out_ready=0
    if (out_valid !== 1'b1 || y !== exp_total) begin
      $display("FAIL transaction 3 pre-stall: out_valid=%0d y=%0d expected=%0d",
                out_valid, y, exp_total);
      errors = errors + 1;
    end

    // stall for several cycles: result and out_valid must not move, and a
    // new input transfer must be ignored while busy (in_ready stays low)
    a = 8'sd99; b = 8'sd99; in_valid = 1;  // try to sneak in a new transfer
    repeat (3) begin
      @(posedge clk); #1;
      if (out_valid !== 1'b1 || y !== exp_total) begin
        $display("FAIL: result changed or dropped during backpressure stall: out_valid=%0d y=%0d expected=%0d",
                  out_valid, y, exp_total);
        errors = errors + 1;
      end
      if (in_ready !== 1'b0) begin
        $display("FAIL: in_ready went high while a result was still waiting to be collected");
        errors = errors + 1;
      end
    end
    in_valid = 0;

    // release backpressure
    out_ready = 1;
    @(posedge clk); #1;
    if (in_ready !== 1'b1 || out_valid !== 1'b0) begin
      $display("FAIL: did not return to idle once out_ready went high: in_ready=%0d out_valid=%0d",
                in_ready, out_valid);
      errors = errors + 1;
    end

    // --- mid-transaction reset takes priority over everything ---
    send(8'sd20, 8'sd20);
    @(posedge clk); #1;                    // now mid-computation (MULT)
    rst = 1;
    @(posedge clk); #1;
    if (in_ready !== 1'b1 || out_valid !== 1'b0 || y !== 0) begin
      $display("FAIL: reset mid-transaction did not return to power-on state: in_ready=%0d out_valid=%0d y=%0d",
                in_ready, out_valid, y);
      errors = errors + 1;
    end
    rst = 0;

    if (errors == 0) $display("ALL TESTS PASSED");
    else             $display("TESTS FAILED: %0d", errors);
    $finish;
  end

  initial begin
    #20000;
    $display("TESTS FAILED: timeout");
    $finish;
  end
endmodule
