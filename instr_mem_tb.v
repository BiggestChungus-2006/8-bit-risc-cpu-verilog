module instruction_memory_tb;

reg clk;
reg [7:0] ext_data;
reg [3:0] pc;

wire [11:0] instr;
reg  [11:0] instr_reg;
reg  zero_reg;
wire branch_taken;

// =====================
// Instruction Memory
// =====================
instr_mem imem (
    .addr(pc),
    .instr(instr)
);

// =====================
// Datapath
// =====================
reg [7:0] ext_data_reg;

datapath uut (
    .clk(clk),
    .ext_data(ext_data_reg),
    .instr(instr_reg)
);

// =====================
// Clock
// =====================
always #5 clk = ~clk;

// =====================
// ZERO FLAG PIPELINE
// =====================
always @(posedge clk) begin
    zero_reg <= uut.zero;
end

// =====================
// BRANCH LOGIC
// =====================
wire is_beq  = (instr_reg[11:9] == 3'b101);
assign branch_taken = (instr_reg[11:9] == 3'b101) && zero_reg;

// =====================
// OFFSET (sign extend)
// =====================
wire signed [3:0] offset;
assign offset = {{1{instr_reg[2]}}, instr_reg[2:0]};

// =====================
// PC UPDATE
// =====================
always @(posedge clk) begin
    if (branch_taken)
        pc <= pc + offset-1;
    else
        pc <= pc + 1;
end



// =====================
// 2-CYCLE FLUSH
// =====================
always @(negedge clk) begin
    if (branch_taken)
        instr_reg <= 12'b000_000_000_000; // NOP
    else
        instr_reg <= instr;
end

// =====================
// EXT DATA PIPELINE
// =====================
always @(negedge clk) begin
    ext_data_reg <= ext_data;
end

// =====================
// INIT + MONITOR
// =====================
initial begin
    $dumpfile("instruction_memory.vcd");
    $dumpvars(0, instruction_memory_tb);

    $monitor("t=%0t | PC=%d | R1=%d R2=%d R3=%d R4=%d R5=%d R6=%d",
        $time, pc,
        uut.rf.regs[1],
        uut.rf.regs[2],
        uut.rf.regs[3],
        uut.rf.regs[4],
        uut.rf.regs[5],
        uut.rf.regs[6],
        uut.alu_result,
        uut.zero
    );

    clk = 0;
    pc = 0;
    instr_reg = 12'b000_000_000_000;
    ext_data_reg = 0;
    zero_reg = 0;
    flush_next = 0;

    ext_data = 10;

    #10;
    ext_data = 5;

    #200;
    $finish;
end

endmodule