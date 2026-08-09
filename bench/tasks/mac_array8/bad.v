// Deliberately WRONG. Failure mode: blocking vs non-blocking assignment in the
// clocked process. `sum` is meant to be a same-cycle temporary but is written
// with a non-blocking assignment and then read in the same process, so `y`
// registers the PREVIOUS cycle's dot product. Compiles and elaborates cleanly;
// only the testbench catches it.
module mac_array8 (
    input  wire               clk,
    input  wire               rst,     // synchronous, active high
    input  wire               en,
    input  wire        [63:0] a_flat,
    input  wire        [63:0] b_flat,
    output reg  signed [31:0] y
);

    integer i;
    reg signed [31:0] prods;
    reg signed [31:0] sum;

    always @(posedge clk) begin
        prods = 32'sd0;
        for (i = 0; i < 8; i = i + 1)
            prods = prods + $signed(a_flat[8*i +: 8]) * $signed(b_flat[8*i +: 8]);

        sum <= prods;               // BUG: should be a blocking assignment

        if (rst) begin
            y <= 32'sd0;
        end else if (en) begin
            y <= sum;               // reads last cycle's value, not this one's
        end
    end

endmodule
