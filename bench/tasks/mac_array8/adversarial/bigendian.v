// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: the byte packing order is misread. The spec says element i is
// at bits [8*i+7:8*i] (element 0 = least significant byte); this unpacks the
// other way round, element 0 = most significant byte. Lints and elaborates
// clean.
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
            for (i = 0; i < 8; i = i + 1)   // BUG: big-endian by element
                acc = acc + $signed(a_flat[8*(7-i) +: 8])
                          * $signed(b_flat[8*(7-i) +: 8]);
            y <= acc;
        end
    end
endmodule
