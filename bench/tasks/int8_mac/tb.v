`timescale 1ns/1ps
// Hand-written. The model under test never sees this file.
module tb;
  reg clk = 0;
  reg rst = 1;
  reg en  = 0;
  reg signed [7:0] a = 0;
  reg signed [7:0] b = 0;
  wire signed [31:0] acc;

  integer errors  = 0;
  integer exp_acc = 0;
  integer i;

  reg signed [7:0] va [0:8];
  reg signed [7:0] vb [0:8];

  int8_mac dut (.clk(clk), .rst(rst), .en(en), .a(a), .b(b), .acc(acc));

  always #5 clk = ~clk;

  initial begin
    va[0] =  8'sd3;   vb[0] =  8'sd4;
    va[1] = -8'sd5;   vb[1] =  8'sd7;
    va[2] =  8'sd127; vb[2] =  8'sd127;
    va[3] = -8'sd127; vb[3] =  8'sd127;
    va[4] =  8'sd0;   vb[4] =  8'sd99;
    va[5] = -8'sd1;   vb[5] = -8'sd1;
    // three more +127*127 (=16129) steps push the running total past 32767
    // (the 16-bit signed range), catching an internal accumulator that's
    // narrower than the 32-bit port and just sign-extended out
    va[6] =  8'sd127; vb[6] =  8'sd127;
    va[7] =  8'sd127; vb[7] =  8'sd127;
    va[8] =  8'sd127; vb[8] =  8'sd127;

    rst = 1; en = 0;
    @(posedge clk); #1;
    if (acc !== 0) begin
      $display("FAIL reset: acc=%0d expected 0", acc);
      errors = errors + 1;
    end

    rst = 0;
    exp_acc = 0;
    for (i = 0; i < 9; i = i + 1) begin
      a = va[i]; b = vb[i]; en = 1;
      @(posedge clk); #1;
      exp_acc = exp_acc + (va[i] * vb[i]);
      if (acc !== exp_acc) begin
        $display("FAIL step %0d (a=%0d b=%0d): acc=%0d expected=%0d",
                 i, va[i], vb[i], acc, exp_acc);
        errors = errors + 1;
      end
    end

    // en low must hold, not accumulate
    en = 0; a = 8'sd50; b = 8'sd50;
    @(posedge clk); #1;
    if (acc !== exp_acc) begin
      $display("FAIL hold with en=0: acc=%0d expected=%0d", acc, exp_acc);
      errors = errors + 1;
    end

    // mid-cycle reset: assert rst strictly between clock edges (not
    // synchronized to a `@(posedge clk)`), which a synchronous design must
    // NOT react to until the following rising edge -- catches an async reset
    en = 1; a = 8'sd5; b = 8'sd5;
    @(posedge clk); #1;
    exp_acc = exp_acc + (5 * 5);
    if (acc !== exp_acc) begin
      $display("FAIL pre-midrst: acc=%0d expected=%0d", acc, exp_acc);
      errors = errors + 1;
    end
    #1 rst = 1;               // assert well inside the current clock period
    #1;
    if (acc !== exp_acc) begin
      $display("FAIL rst reacted before the next clock edge (looks async): acc=%0d expected=%0d (unchanged)", acc, exp_acc);
      errors = errors + 1;
    end
    @(posedge clk); #1;
    if (acc !== 0) begin
      $display("FAIL sync reset did not take effect at the next posedge: acc=%0d expected 0", acc);
      errors = errors + 1;
    end
    rst = 0; en = 0;

    // reset must win over en
    rst = 1; en = 1; a = 8'sd9; b = 8'sd9;
    @(posedge clk); #1;
    if (acc !== 0) begin
      $display("FAIL reset priority over en: acc=%0d expected 0", acc);
      errors = errors + 1;
    end

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
