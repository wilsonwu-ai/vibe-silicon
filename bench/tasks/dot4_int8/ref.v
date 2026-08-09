// Known-good implementation. Exists only to prove tb.v accepts good work.
module dot4_int8 (
    input  wire signed [7:0]  a0, a1, a2, a3,
    input  wire signed [7:0]  b0, b1, b2, b3,
    output wire signed [19:0] y
);
    wire signed [15:0] p0 = a0 * b0;
    wire signed [15:0] p1 = a1 * b1;
    wire signed [15:0] p2 = a2 * b2;
    wire signed [15:0] p3 = a3 * b3;

    assign y = p0 + p1 + p2 + p3;
endmodule
