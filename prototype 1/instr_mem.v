module instr_mem (
    input [3:0] addr,
    output [11:0] instr
);

reg [11:0] memory [15:0];

integer i;
initial begin
    // Initialize all memory to NOPs to avoid unknown states
    for (i = 0; i < 16; i = i + 1)
        memory[i] = 12'b000_000_000_000;

    // Test the LOAD sequence:
    // Instruction 0: LOAD R1, [R0]  -> R1 = DMEM[0] = 10
    memory[0] = 12'b111_000_000_001; 
    
    // Instruction 1: LOAD R2, [R1]  -> R2 = DMEM[10] = 42
    memory[1] = 12'b111_001_000_010; 
end
assign instr = memory[addr];

endmodule
