// LLM-written, human-reviewed. This is the "LLM-written" cell of the README
// table -- not bench/tasks/mac_array8/ref.v (that file is hand-written by us,
// solely to prove tb.v accepts correct work).
//
// Provenance: bench/results/results.jsonl, exact match on
//   {"task": "mac_array8", "lang": "verilog", "model": "claude-sonnet-5",
//    "trial": 0, "ts": "2026-08-09T17:33:09+00:00"}
// generated against bench/tasks/mac_array8/spec.md, passed bench/tasks/mac_array8/tb.v
// in simulation (iverilog) at generation time. Copied verbatim below -- not
// re-generated, not hand-edited.
//
// Human review (2026-08-09): synchronous reset with priority over `en`, no
// latches, every product cast through $signed(), reset/enable structure
// matches the two other passing candidates (claude-opus-5 trial 0,
// claude-haiku-4-5 trial 0) byte for byte in shape -- all three independently
// converged on the same 8x $signed-multiply-then-sum design. Uses 8 of the
// MAX 10 10M50DAF484C6GES's 144 18x18 multipliers.
module mac_array8 (
    input  wire               clk,
    input  wire               rst,     // synchronous, active high
    input  wire               en,
    input  wire        [63:0] a_flat,
    input  wire        [63:0] b_flat,
    output reg  signed [31:0] y
);

    wire signed [7:0] a0 = a_flat[7:0];
    wire signed [7:0] a1 = a_flat[15:8];
    wire signed [7:0] a2 = a_flat[23:16];
    wire signed [7:0] a3 = a_flat[31:24];
    wire signed [7:0] a4 = a_flat[39:32];
    wire signed [7:0] a5 = a_flat[47:40];
    wire signed [7:0] a6 = a_flat[55:48];
    wire signed [7:0] a7 = a_flat[63:56];

    wire signed [7:0] b0 = b_flat[7:0];
    wire signed [7:0] b1 = b_flat[15:8];
    wire signed [7:0] b2 = b_flat[23:16];
    wire signed [7:0] b3 = b_flat[31:24];
    wire signed [7:0] b4 = b_flat[39:32];
    wire signed [7:0] b5 = b_flat[47:40];
    wire signed [7:0] b6 = b_flat[55:48];
    wire signed [7:0] b7 = b_flat[63:56];

    wire signed [15:0] p0 = a0 * b0;
    wire signed [15:0] p1 = a1 * b1;
    wire signed [15:0] p2 = a2 * b2;
    wire signed [15:0] p3 = a3 * b3;
    wire signed [15:0] p4 = a4 * b4;
    wire signed [15:0] p5 = a5 * b5;
    wire signed [15:0] p6 = a6 * b6;
    wire signed [15:0] p7 = a7 * b7;

    wire signed [31:0] sum = $signed(p0) + $signed(p1) + $signed(p2) + $signed(p3) +
                             $signed(p4) + $signed(p5) + $signed(p6) + $signed(p7);

    always @(posedge clk) begin
        if (rst)
            y <= 32'sd0;
        else if (en)
            y <= sum;
    end

endmodule
