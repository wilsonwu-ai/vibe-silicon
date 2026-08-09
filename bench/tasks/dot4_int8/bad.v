// Deliberately WRONG. Failure mode: signedness -- the `signed` qualifier is
// dropped from the ports and the products, so the multiplies are unsigned and
// negative operands become large positives.
// Compiles and elaborates cleanly; only the testbench catches it.
module dot4_int8 (
    input  wire [7:0]  a0, a1, a2, a3,
    input  wire [7:0]  b0, b1, b2, b3,
    output wire [19:0] y
);
    wire [15:0] p0 = a0 * b0;
    wire [15:0] p1 = a1 * b1;
    wire [15:0] p2 = a2 * b2;
    wire [15:0] p3 = a3 * b3;

    assign y = p0 + p1 + p2 + p3;
endmodule
