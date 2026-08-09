// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: wrong bit width truncating the product. The a*b result is 16
// bits wide but is captured in an 8-bit net before being accumulated, so every
// product larger than +-127 is silently truncated. Lints and elaborates clean.
module int8_mac (
    input  wire               clk,
    input  wire               rst,   // synchronous, active high
    input  wire               en,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg  signed [31:0] acc
);
    wire signed [7:0] prod = a * b;   // BUG: 8 bits, should be 16

    always @(posedge clk) begin
        if (rst)
            acc <= 32'sd0;
        else if (en)
            acc <= acc + prod;
    end
endmodule
