`timescale 1ns/1ps

// ============================================================================
// dmem.v - 256 x 8-bit data memory, asynchronous (combinational) read
//
// Every location is initialised to zero, so a LOAD from any address returns a
// defined value (never X). Two locations carry non-zero preset values.
// There is no write port (the ISA has no STORE instruction).
// ============================================================================
module dmem (
    input  [7:0] addr,
    output [7:0] data
);

    reg [7:0] memory [255:0];

    integer k;
    initial begin
        // 1. Zero all 256 locations.
        for (k = 0; k < 256; k = k + 1)
            memory[k] = 8'd0;

        // 2. Preset locations used by the LOAD tests.
        memory[0]  = 8'd10;   // LOAD R1,[R0]  -> R1 = DMEM[0]  = 10
        memory[10] = 8'd42;   // LOAD R2,[R1]  -> R2 = DMEM[10] = 42 (when R1 = 10)
    end

    // Combinational read
    assign data = memory[addr];

endmodule
