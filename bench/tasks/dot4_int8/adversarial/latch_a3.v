// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: latch inference from an incomplete `if` with no `else`. When
// the guard is false (guarded on a3) the output keeps its previous value instead of being
// combinational. Lints and elaborates clean.
module dot4_int8 (
    input  wire signed [7:0]  a0, a1, a2, a3,
    input  wire signed [7:0]  b0, b1, b2, b3,
    output reg  signed [19:0] y
);
    always @* begin
        if (a3 != 8'sd0)                // BUG: no else -> inferred latch
            y = a0*b0 + a1*b1 + a2*b2 + a3*b3;
    end
endmodule
