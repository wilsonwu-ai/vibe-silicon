// Deliberately WRONG. Failure mode: ignores backpressure. `out_valid` is
// asserted for exactly one cycle and the unit returns to idle unconditionally
// regardless of `out_ready`, so a stalled downstream (out_ready held low)
// silently loses the result instead of the unit holding it. Lints and
// elaborates cleanly, and single-transaction tests with out_ready already
// high never observe the difference; only a backpressure test catches it.
module vr_mac (
    input  wire               clk,
    input  wire                rst,
    input  wire                in_valid,
    output reg                  in_ready,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output reg                  out_valid,
    input  wire                out_ready,
    output reg  signed [31:0] y
);

    localparam [1:0]
        S_IDLE  = 2'd0,
        S_MULT  = 2'd1,
        S_ACCUM = 2'd2,
        S_DONE  = 2'd3;

    reg [1:0] state;
    reg signed [7:0]  a_lat, b_lat;
    reg signed [15:0] prod;
    reg signed [31:0] acc;

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            in_ready  <= 1'b1;
            out_valid <= 1'b0;
            acc       <= 32'sd0;
            y         <= 32'sd0;
            a_lat     <= 8'sd0;
            b_lat     <= 8'sd0;
            prod      <= 16'sd0;
        end else begin
            case (state)
                S_IDLE: begin
                    in_ready  <= 1'b1;
                    out_valid <= 1'b0;
                    if (in_valid) begin
                        a_lat    <= a;
                        b_lat    <= b;
                        in_ready <= 1'b0;
                        state    <= S_MULT;
                    end
                end

                S_MULT: begin
                    in_ready <= 1'b0;
                    prod     <= a_lat * b_lat;
                    state    <= S_ACCUM;
                end

                S_ACCUM: begin
                    in_ready  <= 1'b0;
                    acc       <= acc + prod;
                    y         <= acc + prod;
                    out_valid <= 1'b1;
                    state     <= S_DONE;
                end

                S_DONE: begin
                    // BUG: unconditionally drops out_valid and returns to
                    // idle, ignoring out_ready.
                    in_ready  <= 1'b1;
                    out_valid <= 1'b0;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
