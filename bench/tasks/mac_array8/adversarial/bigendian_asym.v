// ADVERSARIAL PROBE (not part of the frozen bench).
// Added 2026-08-09 alongside the note in bigendian.v. Failure mode: only
// b_flat's byte order is misread (a_flat is correct) -- an asymmetric,
// arguably more realistic version of the byte-order mistake, since it does
// not require a model to make the identical error in both unpacks. Unlike
// bigendian.v, this one IS observable at `y`: verified to fail tb.v's case6
// (both operands vary independently per lane).
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
            for (i = 0; i < 8; i = i + 1)          // BUG: b_flat read big-endian
                acc = acc + $signed(a_flat[8*i +: 8])
                          * $signed(b_flat[8*(7-i) +: 8]);
            y <= acc;
        end
    end

endmodule
