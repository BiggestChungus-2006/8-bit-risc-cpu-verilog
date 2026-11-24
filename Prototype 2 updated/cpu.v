`timescale 1ns/1ps

// ============================================================================
// cpu.v - top level: IF stage, IF/ID, branch control; instantiates datapath
//
// Changes vs. the audited snapshot (pipeline behaviour is unchanged):
//   * 'flush' is declared before its first use (was an implicit net)
//   * the retired external-data path (ext_data, ext_data_reg) is removed
// ============================================================================
module cpu (

    input clk,

    output reg [3:0] pc,
    output [11:0] instr,
    output zero,
    output branch_taken

);

// ============================================================
// DECLARATIONS (everything is declared before first use)
// ============================================================

// IF/ID pipeline register
reg [11:0] if_id_instr;
reg [3:0]  if_id_pc;

// ID stage - branch detection
wire is_branch_id;
wire signed [3:0] offset;
wire [3:0] branch_target_id;

// ID/EX pipeline register (control-flow signals only)
reg       id_ex_is_branch;
reg [3:0] id_ex_branch_target;

// A taken branch means the instruction currently in IF/ID and the one being
// latched into datapath.v's ID/EX are both wrong-path. This single signal
// tells both places to neutralise what they are about to latch.
wire flush;


// ============================================================
// INITIAL CPU STATE
// ============================================================

initial begin
    pc = 4'd0;
    if_id_instr = 12'b000_000_000_000;
    if_id_pc    = 4'd0;
    id_ex_is_branch     = 1'b0;
    id_ex_branch_target = 4'd0;
end


// ============================================================
// INSTRUCTION MEMORY
// ============================================================

instr_mem imem (
        .addr(pc),
        .instr(instr)
    );


// ============================================================
// DATAPATH
// ============================================================

datapath dp (
        .clk(clk),
        .instr(if_id_instr),
        .flush(flush),
        .zero(zero)
    );


// ============================================================
// ID STAGE - BRANCH DETECTION (combinational)
// ============================================================

assign is_branch_id = (if_id_instr[11:9] == 3'b110);

assign offset = {{1{if_id_instr[2]}}, if_id_instr[2:0]};

assign branch_target_id = if_id_pc + offset;


// ============================================================
// ID/EX PIPELINE REGISTER (control-flow signals only)
// ============================================================

always @(posedge clk) begin
    if (flush) begin
        id_ex_is_branch     <= 1'b0;
        id_ex_branch_target <= 4'd0;
    end else begin
        id_ex_is_branch     <= is_branch_id;
        id_ex_branch_target <= branch_target_id;
    end
end


// ============================================================
// EX STAGE - BRANCH DECISION (combinational)
// ============================================================

assign branch_taken = id_ex_is_branch && zero;


// ============================================================
// FLUSH SIGNAL
// ============================================================

assign flush = branch_taken;


// ============================================================
// PC UPDATE
// ============================================================

always @(posedge clk) begin

    if (branch_taken)
        pc <= id_ex_branch_target;

    else
        pc <= pc + 1;

end


// ============================================================
// IF/ID PIPELINE REGISTER
// ============================================================

always @(posedge clk) begin
    if (flush) begin
        if_id_instr <= 12'b000_000_000_000;
    end else begin
        if_id_instr <= instr;
    end
    if_id_pc <= pc;
end

endmodule
