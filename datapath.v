module datapath (
    input clk,
    input [7:0] ext_data,
    input [11:0] instr,
    output zero           
);

// --------------------
// Internal wires
// --------------------
wire [7:0] rd1, rd2;
wire [7:0] a_in, b_in;
wire [7:0] alu_result;
wire [7:0] wd;

wire [2:0] opcode;
wire [2:0] rs1, rs2, rd;
wire [2:0] ra1, ra2, wa;
wire [2:0] op;

wire we_internal;
wire sel_internal;

wire carry, overflow;

// --------------------
// Instruction decode
// --------------------
assign opcode = instr[11:9];
assign rs1    = instr[8:6];
assign rs2    = instr[5:3];
assign rd     = instr[2:0];

assign ra1 = rs1;
assign ra2 = rs2;
assign wa  = rd;
assign op = (opcode == 3'b110) ? 3'b001 : opcode;

// --------------------
// Pipeline registers (FOR FORWARDING)
// --------------------
reg [7:0] alu_result_reg;
reg [2:0] wa_reg;
reg we_reg;

always @(posedge clk) begin
    alu_result_reg <= alu_result;   // previous ALU result
    wa_reg <= wa;                  // previous destination register
    we_reg <= we_internal;         // previous write enable
end

// --------------------
// Forwarding logic
// --------------------
assign a_in = (we_reg && (wa_reg == ra1)) ? alu_result_reg : rd1;
assign b_in = (we_reg && (wa_reg == ra2)) ? alu_result_reg : rd2;

// --------------------
// Write data selection
// --------------------
assign wd = (sel_internal) ? ext_data : alu_result;

// --------------------
// Register file
// --------------------
regfile rf (
    .clk(clk),
    .we(we_internal),
    .ra1(ra1),
    .ra2(ra2),
    .wa(wa),
    .wd(wd),
    .rd1(rd1),
    .rd2(rd2)
);

// --------------------
// ALU
// --------------------
the_alu alu (
    .a(a_in),
    .b(b_in),
    .op(op),
    .result(alu_result),
    .zero(zero),
    .carry(carry),
    .overflow(overflow)
);

// --------------------
// Control Unit
// --------------------
control_unit cu (
    .opcode(opcode),
    .we(we_internal),
    .sel(sel_internal)
);

endmodule