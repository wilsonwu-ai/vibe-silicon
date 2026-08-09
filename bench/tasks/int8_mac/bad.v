// DELIBERATELY BROKEN. Failure mode: reset priority inverted.
// The enable is tested before the synchronous reset, so a reset asserted while
// en is high is ignored and the accumulator keeps accumulating. Compiles and
// elaborates cleanly; only the testbench catches it.
module int8_mac (
    input  wire               clk,
    input  wire               rst,   // synchronous, active high
    input  wire               en,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg  signed [31:0] acc
);
    always @(posedge clk) begin
        if (en)
            acc <= acc + (a * b);
        else if (rst)
            acc <= 32'sd0;
    end
endmodule
