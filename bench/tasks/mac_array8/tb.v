`timescale 1ns/1ps
// Hand-written. The model under test never sees this file.
module tb;
  reg clk = 0;
  reg rst = 1;
  reg en  = 0;
  reg [63:0] a_flat = 0;
  reg [63:0] b_flat = 0;
  wire signed [31:0] y;

  integer errors = 0;
  integer exp;
  integer i, k;
  reg signed [7:0] av [0:7];
  reg signed [7:0] bv [0:7];

  mac_array8 dut (.clk(clk), .rst(rst), .en(en),
                  .a_flat(a_flat), .b_flat(b_flat), .y(y));

  always #5 clk = ~clk;

  task load;  // pack the arrays and compute the expected value
    begin
      exp = 0;
      for (k = 0; k < 8; k = k + 1) begin
        a_flat[8*k +: 8] = av[k];
        b_flat[8*k +: 8] = bv[k];
        exp = exp + (av[k] * bv[k]);
      end
    end
  endtask

  initial begin
    rst = 1; en = 0;
    @(posedge clk); #1;
    if (y !== 0) begin
      $display("FAIL reset: y=%0d expected 0", y);
      errors = errors + 1;
    end
    rst = 0;

    // case 1: ascending against a constant
    for (i = 0; i < 8; i = i + 1) begin av[i] = i + 1; bv[i] = 8'sd2; end
    load; en = 1; @(posedge clk); #1;
    if (y !== exp) begin
      $display("FAIL case1: y=%0d expected=%0d", y, exp);
      errors = errors + 1;
    end

    // case 2: negative a, positive b (catches unsigned unpacking)
    for (i = 0; i < 8; i = i + 1) begin av[i] = -(i + 1); bv[i] = 8'sd3; end
    load; @(posedge clk); #1;
    if (y !== exp) begin
      $display("FAIL case2 (signedness): y=%0d expected=%0d", y, exp);
      errors = errors + 1;
    end

    // case 3: both negative, must come out positive
    for (i = 0; i < 8; i = i + 1) begin av[i] = -8'sd127; bv[i] = -8'sd127; end
    load; @(posedge clk); #1;
    if (y !== exp) begin
      $display("FAIL case3: y=%0d expected=%0d", y, exp);
      errors = errors + 1;
    end

    // case 4: mixed signs must cancel to exactly zero
    for (i = 0; i < 8; i = i + 1) begin
      av[i] = (i % 2 == 0) ? 8'sd100 : -8'sd100;
      bv[i] = 8'sd50;
    end
    load; @(posedge clk); #1;
    if (y !== exp || y !== 0) begin
      $display("FAIL case4: y=%0d expected=%0d (0)", y, exp);
      errors = errors + 1;
    end

    // case 5: replaces, does not accumulate
    for (i = 0; i < 8; i = i + 1) begin av[i] = 8'sd1; bv[i] = 8'sd1; end
    load; @(posedge clk); #1;
    if (y !== 8) begin
      $display("FAIL case5 (accumulated instead of replaced): y=%0d expected 8", y);
      errors = errors + 1;
    end

    // en low holds
    en = 0;
    for (i = 0; i < 8; i = i + 1) begin av[i] = 8'sd9; bv[i] = 8'sd9; end
    load; @(posedge clk); #1;
    if (y !== 8) begin
      $display("FAIL hold with en=0: y=%0d expected 8", y);
      errors = errors + 1;
    end

    // reset beats en
    rst = 1; en = 1;
    @(posedge clk); #1;
    if (y !== 0) begin
      $display("FAIL reset priority over en: y=%0d expected 0", y);
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
