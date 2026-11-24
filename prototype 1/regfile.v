module regfile (
    input clk,
    input we,                 // write enable
    input [2:0] ra1, ra2,     // read addresses
    input [2:0] wa,           // write address
    input [7:0] wd,           // write data

    output [7:0] rd1, rd2     // read data
);

// 8 registers of 8 bits
reg [7:0] regs [7:0];

// Read (combinational)
assign rd1 = regs[ra1];
assign rd2 = regs[ra2];

integer i;
initial begin
    for (i = 0; i < 8; i = i + 1)
        regs[i] = 0;
end
// Write (sequential)
always @(posedge clk) begin
    if (we)
        regs[wa] <= wd;
end

endmodule