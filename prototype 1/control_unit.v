module control_unit (
    input [2:0] opcode,
    output reg we,
    output reg sel
);

always @(*) begin
    case(opcode)

        3'b111: begin   // LOAD
            we  = 1;
            sel = 1;
        end

        3'b110: begin   // BEQ — fixed: was 3'b101, doesn't match instr_mem.v encoding
            we  = 0;
            sel = 0;
        end

        default: begin  // ALL ALU operations
            we  = 1;
            sel = 0;
        end

    endcase
end

endmodule