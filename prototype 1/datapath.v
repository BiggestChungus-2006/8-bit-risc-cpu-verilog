module datapath (
    input clk,
    input [7:0] ext_data,
    input [11:0] instr,
    input flush,
    output zero
);

// ============================================================
// 1. ID STAGE — DECODE THE INSTRUCTION
// ============================================================
wire [2:0] opcode, rs1, rs2, rd;

assign opcode = instr[11:9];
assign rs1    = instr[8:6];
assign rs2    = instr[5:3];
assign rd     = instr[2:0];

wire [2:0] ra1, ra2, wa;
assign ra1 = rs1;
assign ra2 = rs2;
assign wa  = rd;

wire [2:0] op;
assign op = (opcode == 3'b110) ? 3'b001 : opcode;

// ============================================================
// 2. ID STAGE — CONTROL UNIT + REGISTER FILE READ
// ============================================================
wire [7:0] rd1, rd2;
wire we_internal, sel_internal;

control_unit cu (
    .opcode(opcode),
    .we(we_internal),
    .sel(sel_internal)
);

// ============================================================
// 3. ID STAGE — WB → ID FORWARDING
// ============================================================
wire fwd_id_wb_1 =
    mem_wb_we &&
    (mem_wb_rd == ra1) &&
    (ra1 != 3'b000);

wire fwd_id_wb_2 =
    mem_wb_we &&
    (mem_wb_rd == ra2) &&
    (ra2 != 3'b000);

wire [7:0] rd1_final =
    fwd_id_wb_1 ? mem_wb_wd : rd1;

wire [7:0] rd2_final =
    fwd_id_wb_2 ? mem_wb_wd : rd2;

// ============================================================
// 4. ID/EX PIPELINE REGISTER
// ============================================================
reg [7:0] id_ex_rd1, id_ex_rd2;
reg [2:0] id_ex_op;
reg [2:0] id_ex_rd;
reg       id_ex_we;
reg       id_ex_sel;
reg [7:0] id_ex_ext_data;
reg [2:0] id_ex_rs1;
reg [2:0] id_ex_rs2;

always @(posedge clk) begin
    if (flush) begin
        id_ex_rd1      <= 8'd0;
        id_ex_rd2      <= 8'd0;
        id_ex_op       <= 3'd0;
        id_ex_rd       <= 3'd0;
        id_ex_we       <= 1'b0;
        id_ex_sel      <= 1'b0;
        id_ex_ext_data <= 8'd0;
        id_ex_rs1      <= 3'd0;
        id_ex_rs2      <= 3'd0;
    end else begin
        id_ex_rd1      <= rd1_final;
        id_ex_rd2      <= rd2_final;
        id_ex_op       <= op;
        id_ex_rd       <= wa;
        id_ex_we       <= we_internal;
        id_ex_sel      <= sel_internal;
        id_ex_ext_data <= ext_data;
        id_ex_rs1      <= rs1;
        id_ex_rs2      <= rs2;
    end
end

// ============================================================
// 5. EX STAGE — FORWARDING
// ============================================================
wire [7:0] mem_stage_value;

// FIX TASK 3: Forward the actual output of the MEM stage
// Use the combinational memory output for LOADs in the MEM stage.
assign mem_stage_value =
    ex_mem_sel ? mem_wd : ex_mem_alu_result;

wire fwd_ex_mem_a =
    ex_mem_we &&
    (ex_mem_rd == id_ex_rs1) &&
    (id_ex_rs1 != 3'b000);

wire fwd_mem_wb_a =
    mem_wb_we &&
    (mem_wb_rd == id_ex_rs1) &&
    (id_ex_rs1 != 3'b000);

wire fwd_ex_mem_b =
    ex_mem_we &&
    (ex_mem_rd == id_ex_rs2) &&
    (id_ex_rs2 != 3'b000);

wire fwd_mem_wb_b =
    mem_wb_we &&
    (mem_wb_rd == id_ex_rs2) &&
    (id_ex_rs2 != 3'b000);

wire [7:0] a_in =
    fwd_ex_mem_a ? mem_stage_value :
    fwd_mem_wb_a ? mem_wb_wd :
                   id_ex_rd1;

wire [7:0] b_in =
    fwd_ex_mem_b ? mem_stage_value :
    fwd_mem_wb_b ? mem_wb_wd :
                   id_ex_rd2;

// ============================================================
// 6. EX STAGE — ALU
// ============================================================
wire [7:0] alu_result;
wire carry, overflow;

the_alu alu (
    .a(a_in),
    .b(b_in),
    .op(id_ex_op),
    .result(alu_result),
    .zero(zero),
    .carry(carry),
    .overflow(overflow)
);

// ============================================================
// 7. EX/MEM PIPELINE REGISTER
// ============================================================
reg [7:0] ex_mem_alu_result;
reg [2:0] ex_mem_rd;
reg       ex_mem_we;
reg       ex_mem_sel;
reg [7:0] ex_mem_addr; // FIX TASK 1: Registered address for MEM stage

always @(posedge clk) begin
    ex_mem_alu_result <= alu_result;
    ex_mem_rd         <= id_ex_rd;
    ex_mem_we         <= id_ex_we;
    ex_mem_sel        <= id_ex_sel;
    ex_mem_addr       <= a_in; // FIX TASK 1: Address travels with the instruction
end

// ============================================================
// 8. MEM STAGE
// ============================================================
wire [7:0] mem_wd;

// FIX TASK 1 & 2: Connect dmem to the registered EX/MEM address
dmem dm (
    .addr(ex_mem_addr),
    .data(mem_wd)
);

// FIX TASK 2: Memory output aligned with current instruction in MEM
wire [7:0] mem_out;
assign mem_out = ex_mem_sel ? mem_wd : ex_mem_alu_result;

// ============================================================
// 9. MEM/WB PIPELINE REGISTER
// ============================================================
reg [7:0] mem_wb_wd;
reg [2:0] mem_wb_rd;
reg       mem_wb_we;

always @(posedge clk) begin
    mem_wb_wd <= mem_out; // Latch the correctly aligned MEM result
    mem_wb_rd <= ex_mem_rd;
    mem_wb_we <= ex_mem_we;
end

// ============================================================
// 10. WB STAGE — REGISTER FILE WRITE
// ============================================================
regfile rf (
    .clk(clk),
    .we(mem_wb_we),
    .ra1(ra1),
    .ra2(ra2),
    .wa(mem_wb_rd),
    .wd(mem_wb_wd),
    .rd1(rd1),
    .rd2(rd2)
);

endmodule
