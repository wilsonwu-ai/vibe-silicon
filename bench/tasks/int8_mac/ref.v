// Known-good reference implementation. Used only to prove tb.v accepts correct
// work. The model under test never sees this file.
module int8_mac (
    input  wire               clk,
    input  wire               rst,   // synchronous, active high
    input  wire               en,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg  signed [31:0] acc
);
    always @(posedge clk) begin
        if (rst)
            acc <= 32'sd0;
        else if (en)
            acc <= acc + (a * b);
    end
endmodule
