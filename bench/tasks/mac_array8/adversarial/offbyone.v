// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: off-by-one in the accumulate loop. Element 7 is never summed.
// Lints and elaborates clean.
module mac_array8 (
    input  wire               clk,
    input  wire               rst,     // synchronous, active high
    input  wire               en,
    input  wire        [63:0] a_flat,
    input  wire        [63:0] b_flat,
    output reg  signed [31:0] y
);
    integer i;
    reg signed [31:0] acc;

    always @(posedge clk) begin
        if (rst) begin
            y <= 32'sd0;
        end else if (en) begin
            acc = 32'sd0;
            for (i = 0; i < 7; i = i + 1)   // BUG: drops element 7
                acc = acc + $signed(a_flat[8*i +: 8]) * $signed(b_flat[8*i +: 8]);
            y <= acc;
        end
    end
endmodule
