`timescale 1ns/1ps

// ============================================================================
// datapath.v - ID / EX / MEM / WB stages of the 5-stage pipeline
//
// Changes vs. the audited snapshot (pipeline structure and forwarding are
// unchanged):
//   * every net and register is declared before its first use
//   * all pipeline registers have a defined start-up value (no X at power-up)
//   * the retired external-data path (ext_data / id_ex_ext_data) is removed
//
// LOAD semantics:  R[rd] = DMEM[R[rs1]]   (asynchronous-read data memory)
// ============================================================================
module datapath (
    input         clk,
    input  [11:0] instr,     // instruction currently in ID (from IF/ID in cpu.v)
    input         flush,     // taken-branch flush (from cpu.v)
    output        zero       // ALU zero flag of the instruction currently in EX
);

// ============================================================
// 0. DECLARATIONS (everything is declared before first use)
// ============================================================

// --- ID stage: decode ---
wire [2:0] opcode, rs1, rs2, rd;
wire [2:0] ra1, ra2, wa;
wire [2:0] op;
wire [7:0] rd1, rd2;                 // register-file read data
wire       we_internal, sel_internal;
wire       mem_write_internal;

// --- WB -> ID forwarding ---
wire       fwd_id_wb_1, fwd_id_wb_2;
wire [7:0] rd1_final, rd2_final;

// --- ID/EX pipeline register ---
reg [7:0] id_ex_rd1, id_ex_rd2;
reg [2:0] id_ex_op;
reg [2:0] id_ex_rd;
reg       id_ex_we;
reg       id_ex_sel;
reg       id_ex_mem_write;
reg [2:0] id_ex_rs1;
reg [2:0] id_ex_rs2;

// --- EX/MEM pipeline register ---
reg [7:0] ex_mem_alu_result;
reg [2:0] ex_mem_rd;
reg       ex_mem_we;
reg       ex_mem_sel;
reg [7:0] ex_mem_addr;               // data-memory address travels with the instruction

// --- MEM/WB pipeline register ---
reg [7:0] mem_wb_wd;
reg [2:0] mem_wb_rd;
reg       mem_wb_we;

// --- MEM stage ---
wire [7:0] mem_wd;                   // asynchronous data-memory read data
wire [7:0] mem_out;                  // value handed to MEM/WB

// --- EX stage: forwarding + ALU ---
wire [7:0] mem_stage_value;
wire       fwd_ex_mem_a, fwd_mem_wb_a, fwd_ex_mem_b, fwd_mem_wb_b;
wire [7:0] a_in, b_in;
wire [7:0] alu_result;
wire       carry, overflow;

// ============================================================
// 0b. START-UP STATE
//     Every pipeline register starts as a harmless bubble (we = 0, rd = 0),
//     so all forwarding control signals are deterministic from time 0.
// ============================================================
initial begin
    id_ex_rd1         = 8'd0;
    id_ex_rd2         = 8'd0;
    id_ex_op          = 3'd0;
    id_ex_rd          = 3'd0;
    id_ex_we          = 1'b0;
    id_ex_sel         = 1'b0;
    id_ex_mem_write   = 1'b0;
    id_ex_rs1         = 3'd0;
    id_ex_rs2         = 3'd0;

    ex_mem_alu_result = 8'd0;
    ex_mem_rd         = 3'd0;
    ex_mem_we         = 1'b0;
    ex_mem_sel        = 1'b0;
    ex_mem_addr       = 8'd0;

    mem_wb_wd         = 8'd0;
    mem_wb_rd         = 3'd0;
    mem_wb_we         = 1'b0;
end

// ============================================================
// 1. ID STAGE - DECODE THE INSTRUCTION
// ============================================================
assign opcode = instr[11:9];
assign rs1    = instr[8:6];
assign rs2    = instr[5:3];
assign rd     = instr[2:0];

assign ra1 = rs1;
assign ra2 = rs2;
assign wa  = rd;

// BEQ is executed as a subtraction; its ALU zero flag is the equality result.
assign op = (opcode == 3'b110) ? 3'b001 : opcode;

// ============================================================
// 2. ID STAGE - CONTROL UNIT
// ============================================================
control_unit cu (
    .opcode(opcode),
    .rs2(rs2),
    .we(we_internal),
    .sel(sel_internal),
    .mem_write(mem_write_internal)
);

// ============================================================
// 3. ID STAGE - WB -> ID FORWARDING
// ============================================================
assign fwd_id_wb_1 =
    mem_wb_we &&
    (mem_wb_rd == ra1) &&
    (ra1 != 3'b000);

assign fwd_id_wb_2 =
    mem_wb_we &&
    (mem_wb_rd == ra2) &&
    (ra2 != 3'b000);

assign rd1_final = fwd_id_wb_1 ? mem_wb_wd : rd1;
assign rd2_final = fwd_id_wb_2 ? mem_wb_wd : rd2;

// ============================================================
// 4. ID/EX PIPELINE REGISTER
// ============================================================
always @(posedge clk) begin
    if (flush) begin
        id_ex_rd1        <= 8'd0;
        id_ex_rd2        <= 8'd0;
        id_ex_op         <= 3'd0;
        id_ex_rd         <= 3'd0;
        id_ex_we         <= 1'b0;
        id_ex_sel        <= 1'b0;
        id_ex_mem_write  <= 1'b0;
        id_ex_rs1        <= 3'd0;
        id_ex_rs2        <= 3'd0;
    end else begin
        id_ex_rd1        <= rd1_final;
        id_ex_rd2        <= rd2_final;
        id_ex_op         <= op;
        id_ex_rd         <= wa;
        id_ex_we         <= we_internal;
        id_ex_sel        <= sel_internal;
        id_ex_mem_write  <= mem_write_internal;
        id_ex_rs1        <= rs1;
        id_ex_rs2        <= rs2;
    end
end

// ============================================================
// 5. EX STAGE - FORWARDING
//    Priority: EX/MEM (youngest) > MEM/WB > ID/EX register read.
// ============================================================

// Value produced by the instruction currently in MEM: loaded data for a LOAD,
// otherwise its ALU result.
assign mem_stage_value = ex_mem_sel ? mem_wd : ex_mem_alu_result;

assign fwd_ex_mem_a =
    ex_mem_we &&
    (ex_mem_rd == id_ex_rs1) &&
    (id_ex_rs1 != 3'b000);

assign fwd_mem_wb_a =
    mem_wb_we &&
    (mem_wb_rd == id_ex_rs1) &&
    (id_ex_rs1 != 3'b000);

assign fwd_ex_mem_b =
    ex_mem_we &&
    (ex_mem_rd == id_ex_rs2) &&
    (id_ex_rs2 != 3'b000);

assign fwd_mem_wb_b =
    mem_wb_we &&
    (mem_wb_rd == id_ex_rs2) &&
    (id_ex_rs2 != 3'b000);

assign a_in =
    fwd_ex_mem_a ? mem_stage_value :
    fwd_mem_wb_a ? mem_wb_wd :
                   id_ex_rd1;

assign b_in =
    fwd_ex_mem_b ? mem_stage_value :
    fwd_mem_wb_b ? mem_wb_wd :
                   id_ex_rd2;

// ============================================================
// 6. EX STAGE - ALU
// ============================================================
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
//    ex_mem_addr = forwarded rs1 value; for a LOAD this is the memory address.
// ============================================================
always @(posedge clk) begin
    ex_mem_alu_result <= alu_result;
    ex_mem_rd         <= id_ex_rd;
    ex_mem_we         <= id_ex_we;
    ex_mem_sel        <= id_ex_sel;
    ex_mem_addr       <= a_in;
end

// ============================================================
// 8. MEM STAGE (asynchronous-read data memory)
// ============================================================
dmem dm (
    .addr(ex_mem_addr),
    .data(mem_wd)
);

assign mem_out = ex_mem_sel ? mem_wd : ex_mem_alu_result;

// ============================================================
// 9. MEM/WB PIPELINE REGISTER
// ============================================================
always @(posedge clk) begin
    mem_wb_wd <= mem_out;
    mem_wb_rd <= ex_mem_rd;
    mem_wb_we <= ex_mem_we;
end

// ============================================================
// 10. WB STAGE - REGISTER FILE WRITE
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
