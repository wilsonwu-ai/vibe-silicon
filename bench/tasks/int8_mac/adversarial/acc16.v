module int8_mac (input wire clk, input wire rst, input wire en,
  input wire signed [7:0] a, input wire signed [7:0] b,
  output reg signed [31:0] acc);
  reg signed [15:0] r;
  always @(posedge clk) begin
    if (rst) r <= 0; else if (en) r <= r + (a*b);
  end
  always @* acc = {{16{r[15]}}, r};
endmodule
