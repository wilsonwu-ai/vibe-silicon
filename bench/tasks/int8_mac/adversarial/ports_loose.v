module int8_mac (input wire clk, input wire rst, input wire en,
  input wire [7:0] a, input wire [7:0] b, output reg [31:0] acc);
  always @(posedge clk) begin
    if (rst) acc <= 32'd0;
    else if (en) acc <= $signed(acc) + ($signed(a) * $signed(b));
  end
endmodule
