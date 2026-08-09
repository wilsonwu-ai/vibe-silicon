// ADVERSARIAL PROBE (not part of the frozen bench).
// Failure mode: the byte packing order is misread. The spec says element i is
// at bits [8*i+7:8*i] (element 0 = least significant byte); this unpacks the
// other way round, element 0 = most significant byte. Lints and elaborates
// clean.
//
// UPDATE (2026-08-09, benchmark hardening pass): this file is NOT actually
// detectable by any testbench that only observes `y`, no matter the vectors.
// It reverses BOTH a_flat and b_flat by the same index permutation, and
// sum_i a[sigma(i)]*b[sigma(i)] == sum_i a[i]*b[i] for any bijection sigma --
// a symmetric reversal of a dot product is mathematically identical to the
// unreversed one. tb.v's new case6 (both operands vary independently) was
// added believing it would catch this and does NOT -- verified by running it
// here. It does catch the more realistic *asymmetric* mistake (only one of
// the two operands unpacked backwards); see adversarial/bigendian_asym.v.
// Left in place, with this note, rather than deleted, because "a bug that
// cannot be observed at the output" is itself worth recording.
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
