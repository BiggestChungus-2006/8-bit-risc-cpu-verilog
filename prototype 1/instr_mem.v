module instr_mem (
    input [3:0] addr,          // address (PC)
    output [11:0] instr        // instruction output
);

reg [11:0] memory [15:0];     // 16 instructions

initial begin
    // Original program
    memory[0] = 12'b111_000_000_001; // LOAD R1 = 10
memory[1] = 12'b111_000_000_010; // LOAD R2 = 5

// NOPs (for pipeline safety)
memory[2] = 12'b000_000_000_000;
memory[3] = 12'b000_000_000_000;

// Normal ops
memory[4] = 12'b000_001_010_011; // ADD R1,R2 → R3
memory[5] = 12'b001_001_010_100; // SUB → R4

// 🔥 LOOP START
// LOOP START
memory[6] = 12'b110_001_000_011; // BEQ R1,R0 → EXIT (+3)

memory[7] = 12'b001_001_010_001; // SUB R1,R2 → R1

memory[8] = 12'b110_000_000_110; // BEQ R0,R0 → LOOP BACK (-2)

// EXIT
memory[9] = 12'b000_001_010_011; // ADD (end)

// EXIT
memory[10] = 12'b000_001_010_011; // ADD (end)
end
assign instr = memory[addr];

endmodule