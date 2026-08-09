// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: reset made ASYNCHRONOUS when the spec says synchronous.
// Different hardware, different timing closure, different reset-release
// behaviour. Lints and elaborates clean.
module int8_mac (
    input  wire               clk,
    input  wire               rst,   // spec says SYNCHRONOUS, active high
    input  wire               en,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg  signed [31:0] acc
);
    always @(posedge clk or posedge rst) begin   // BUG: async reset
        if (rst)
            acc <= 32'sd0;
        else if (en)
            acc <= acc + (a * b);
    end
endmodule
