`timescale 1ns/1ps

module the_alu (
    input [7:0] a, b,       // 8-bit inputs
    input [2:0] op,         // operation select
    output reg [7:0] result, // 8-bit output
    output reg zero,
    output reg carry,
    output reg overflow
);

always @(*) begin

    carry = 0;
    overflow = 0;
    result = 0;
    
    case(op)
        3'b000: begin // ADD
            {carry, result} = a + b;
            overflow = (a[7] == b[7]) && (result[7] != a[7]);
        end                         // ADD
        3'b001: begin // SUB
            {carry, result} = a - b;
            overflow = (a[7] != b[7]) && (result[7] != a[7]);
        end
                         // SUB
        3'b010: result = a & b;                         // AND
        3'b011: result = a | b;                         // OR
        3'b100: result = (a < b) ? 8'd1 : 8'd0;         // SLT (Set Less Than)
        3'b101: result = a ^ b;                 // XOR
        3'b110: begin // SHIFT LEFT
            carry = a[7];     // MSB out
            result = a << 1;
        end               
        3'b111: begin // SHIFT RIGHT
            carry = a[0];     // LSB out
            result = a >> 1;
        end  
        default: result = 8'd0;
    endcase
    zero = (result == 0);
end

endmodule