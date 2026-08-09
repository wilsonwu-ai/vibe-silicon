`timescale 1ns/1ps
// Hand-written. The model under test never sees this file.
module tb;
  reg signed [7:0] a0, a1, a2, a3;
  reg signed [7:0] b0, b1, b2, b3;
  wire signed [19:0] y;

  integer errors = 0;
  integer exp;

  dot4_int8 dut (
    .a0(a0), .a1(a1), .a2(a2), .a3(a3),
    .b0(b0), .b1(b1), .b2(b2), .b3(b3),
    .y(y)
  );

  task apply;
    input signed [7:0] p0, p1, p2, p3;
    input signed [7:0] q0, q1, q2, q3;
    begin
      a0 = p0; a1 = p1; a2 = p2; a3 = p3;
      b0 = q0; b1 = q1; b2 = q2; b3 = q3;
      exp = p0*q0 + p1*q1 + p2*q2 + p3*q3;
      #1;
      if (y !== exp) begin
        $display("FAIL: got %0d expected %0d", y, exp);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    apply( 8'sd1,  8'sd2,  8'sd3,  8'sd4,   8'sd5, 8'sd6, 8'sd7, 8'sd8);
    apply(-8'sd1, -8'sd2, -8'sd3, -8'sd4,   8'sd5, 8'sd6, 8'sd7, 8'sd8);
    apply( 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127);
    apply(-8'sd127, 8'sd127, -8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127);
    apply( 8'sd0, 8'sd0, 8'sd0, 8'sd0,   8'sd42, 8'sd42, 8'sd42, 8'sd42);
    apply(-8'sd100, 8'sd50, -8'sd25, 8'sd12,  8'sd3, -8'sd4, 8'sd5, -8'sd6);
    apply( 8'sd1, 8'sd0, 8'sd0, 8'sd0,  -8'sd1, 8'sd0, 8'sd0, 8'sd0);

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
