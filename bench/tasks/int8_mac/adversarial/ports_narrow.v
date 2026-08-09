module int8_mac (input wire clk, input wire rst, input wire en,
  input wire signed [7:0] a, input wire signed [7:0] b,
  output reg signed [15:0] acc);
  always @(posedge clk) begin
    if (rst) acc <= 0; else if (en) acc <= acc + (a*b);
  end
endmodule
