`timescale 1ns/1ps

module control_unit (
    input [2:0] opcode,
    input [2:0] rs2,
    output reg we,
    output reg sel,
    output reg mem_write
);

always @(*) begin
    we  = 0;
    sel = 0;
    mem_write = 0;

    case(opcode)

        3'b111: begin   // LOAD / STORE / reserved
            if (rs2 == 3'b000) begin   // LOAD
                we  = 1;
                sel = 1;
                mem_write = 0;
            end else if (rs2 == 3'b111) begin   // STORE
                we  = 0;
                sel = 0;
                mem_write = 1;
            end else begin   // reserved rs2 001-110: no-op
                we  = 0;
                sel = 0;
                mem_write = 0;
            end
        end

        3'b110: begin   // BEQ
            we  = 0;
            sel = 0;
            mem_write = 0;
        end

        default: begin  // ALL ALU operations
            we  = 1;
            sel = 0;
            mem_write = 0;
        end

    endcase
end

endmodule