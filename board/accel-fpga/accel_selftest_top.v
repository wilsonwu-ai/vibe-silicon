`timescale 1ns/1ps
// Standalone, self-checking demo prop for the mac_array8 accelerator.
// Not part of bench/'s CONTRACT.md apparatus -- hand-written for this board.
//
// Drives mac_array8 through the same 10 checks bench/tasks/mac_array8/tb.v
// already proves in simulation (same vectors, same order, same expected
// values -- no new test data invented here). No host interaction required:
// the result is readable at a glance on LEDR.
//
//   LEDR: off               -- not yet run (just after power-up)
//         chasing (1 of 8)  -- self-test running (~4 Hz steps, so it's
//                               visible -- at the raw 50 MHz clock all 10
//                               checks would finish in under a microsecond)
//         steady on, all 10 -- PASS
//         blinking, all 10  -- FAIL (sticky; stays failed until KEY0)
//
//   KEY0: active-low push-button, re-arms and re-runs the self-test.
//
// Only KEY[0] is used (PIN_B8); KEY[1] (PIN_A7) is left off this port list
// entirely to avoid an unused-input warning on a pin this design has no use
// for.
module accel_selftest_top #(
    // 50e6/4 - 1 by default (~4 Hz, for real hardware). Overridable so a
    // testbench can simulate a handful of clocks per tick instead of 12.5M.
    parameter [25:0] TICK_MAX = 26'd12_499_999
) (
    input  wire       CLOCK_50,
    input  wire       KEY0,     // active-low push-button, PIN_B8
    output wire [9:0] LEDR
);

    wire clk = CLOCK_50;

    // ---- KEY0: synchronize the async button into `clk`, then edge-detect a
    // single-cycle restart pulse. (Debounced in hardware already by the
    // board's own Schmitt-trigger input; this is just metastability sync.)
    reg [2:0] key0_sync;
    always @(posedge clk)
        key0_sync <= {key0_sync[1:0], ~KEY0};   // active-high "pressed" once synced
    wire restart_pulse = key0_sync[1] & ~key0_sync[2];

    // ---- ~4 Hz tick off the 50 MHz clock -- slow enough to actually see on
    // stage; paces both the sequencer and the LED chase/blink.
    reg [25:0] tick_cnt = 26'd0;
    reg        tick     = 1'b0;
    always @(posedge clk) begin
        if (tick_cnt == TICK_MAX) begin
            tick_cnt <= 26'd0;
            tick     <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 26'd1;
            tick     <= 1'b0;
        end
    end

    // ---- per-step stimulus / expected value, mirrors tb.v's cases 1-7 plus
    // its reset/en-hold/reset-priority checks. Packing is little-endian by
    // element, byte i in bits [8*i +: 8], per spec.md.
    reg [3:0]         step = 4'd0;      // 0..9 = checks in progress, 10 = done
    reg                fail_latch = 1'b0;

    reg [63:0]         a_flat, b_flat;
    reg                dut_rst, dut_en;
    reg  signed [31:0] expected_y;

    always @(*) begin
        // defaults -- covers step==10 (done/parked) and keeps this latch-free
        a_flat     = 64'd0;
        b_flat     = 64'd0;
        dut_rst    = 1'b0;
        dut_en     = 1'b0;
        expected_y = 32'sd0;
        case (step)
            // 0: power-on reset -> y == 0
            4'd0: begin dut_rst = 1'b1; end
            // 1: case1 -- ascending a (1..8) vs constant b=2 -> 72
            4'd1: begin
                a_flat = 64'h0807060504030201; b_flat = 64'h0202020202020202;
                dut_en = 1'b1; expected_y = 32'sd72;
            end
            // 2: case2 -- negative a (-1..-8), positive b=3 (unsigned-unpacking canary) -> -108
            4'd2: begin
                a_flat = 64'hF8F9FAFBFCFDFEFF; b_flat = 64'h0303030303030303;
                dut_en = 1'b1; expected_y = -32'sd108;
            end
            // 3: case3 -- both operands -127 in every lane -> 129032
            4'd3: begin
                a_flat = 64'h8181818181818181; b_flat = 64'h8181818181818181;
                dut_en = 1'b1; expected_y = 32'sd129032;
            end
            // 4: case4 -- alternating +-100 vs constant b=50, cancels to 0
            4'd4: begin
                a_flat = 64'h9C649C649C649C64; b_flat = 64'h3232323232323232;
                dut_en = 1'b1; expected_y = 32'sd0;
            end
            // 5: case5 -- replaces, does not accumulate -> 8
            4'd5: begin
                a_flat = 64'h0101010101010101; b_flat = 64'h0101010101010101;
                dut_en = 1'b1; expected_y = 32'sd8;
            end
            // 6: case6 -- byte-order sensitive, both operands vary independently -> 120
            4'd6: begin
                a_flat = 64'h0807060504030201; b_flat = 64'h0102030405060708;
                dut_en = 1'b1; expected_y = 32'sd120;
            end
            // 7: case7 -- partial sums exceed 16 bits -> 129032
            4'd7: begin
                a_flat = 64'h7F7F7F7F7F7F7F7F; b_flat = 64'h7F7F7F7F7F7F7F7F;
                dut_en = 1'b1; expected_y = 32'sd129032;
            end
            // 8: en=0 must hold, not recompute -> unchanged from step 7 (129032)
            4'd8: begin
                a_flat = 64'h0909090909090909; b_flat = 64'h0909090909090909;
                dut_en = 1'b0; expected_y = 32'sd129032;
            end
            // 9: rst beats en -> 0
            4'd9: begin
                a_flat = 64'h0909090909090909; b_flat = 64'h0909090909090909;
                dut_rst = 1'b1; dut_en = 1'b1; expected_y = 32'sd0;
            end
            default: ; // step==10: done/parked, defaults above hold
        endcase
    end

    wire signed [31:0] y;

    mac_array8 dut (
        .clk    (clk),
        .rst    (dut_rst),
        .en     (dut_en),
        .a_flat (a_flat),
        .b_flat (b_flat),
        .y      (y)
    );

    // ---- sequencer: on each tick, check the CURRENT step's result, then
    // advance. A mismatch anywhere sticks the fail latch for the whole run.
    always @(posedge clk) begin
        if (restart_pulse) begin
            step       <= 4'd0;
            fail_latch <= 1'b0;
        end else if (tick && step < 4'd10) begin
            if (y != expected_y)
                fail_latch <= 1'b1;
            step <= step + 4'd1;
        end
    end

    // ---- LED chase while running (one lit bit walking through an 8-bit
    // ring), reset to bit 0 on restart.
    reg [7:0] chase = 8'b0000_0001;
    always @(posedge clk) begin
        if (restart_pulse)
            chase <= 8'b0000_0001;
        else if (tick && step < 4'd10)
            chase <= {chase[6:0], chase[7]};
    end

    // ---- ~2 Hz blink for the fail display (toggles every tick)
    reg blink = 1'b0;
    always @(posedge clk)
        if (tick) blink <= ~blink;

    wire done = (step == 4'd10);
    wire pass = done & ~fail_latch;

    assign LEDR = !done          ? {2'b00, chase} :
                  pass           ? 10'b11_1111_1111 :
                  /* fail */       {10{blink}};

endmodule
