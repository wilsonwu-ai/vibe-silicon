// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: incomplete sensitivity list on a combinational block -- the
// Verilog-2001 cousin of latch inference. The b* operands are missing, so the
// block does not re-evaluate when they change. Lints and elaborates clean.
module dot4_int8 (
    input  wire signed [7:0]  a0, a1, a2, a3,
    input  wire signed [7:0]  b0, b1, b2, b3,
    output reg  signed [19:0] y
);
    always @(a0 or a1 or a2 or a3)      // BUG: b0..b3 missing
        y = a0*b0 + a1*b1 + a2*b2 + a3*b3;
endmodule
