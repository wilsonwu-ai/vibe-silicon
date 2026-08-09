// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: wrong intermediate width. The four 16-bit products are summed
// in a 16-bit net, so the sum wraps before it is widened to the 20-bit output.
// Lints and elaborates clean.
module dot4_int8 (
    input  wire signed [7:0]  a0, a1, a2, a3,
    input  wire signed [7:0]  b0, b1, b2, b3,
    output wire signed [19:0] y
);
    // BUG: 16 bits cannot hold 4 x 127 x 127 = 64516
    wire signed [15:0] s = a0*b0 + a1*b1 + a2*b2 + a3*b3;

    assign y = s;
endmodule
