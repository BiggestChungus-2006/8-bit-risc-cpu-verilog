module alu_tb;

reg [7:0] a, b;
reg [2:0] op;
wire [7:0] result;
wire zero, carry, overflow;

the_alu uut (
    .a(a),
    .b(b),
    .op(op),
    .result(result),
    .zero(zero),
    .carry(carry),
    .overflow(overflow)
);

initial begin
    $monitor("op=%b | a=%d b=%d | result=%d | Z=%b C=%b V=%b",
              op, a, b, result, zero, carry, overflow);

    // ADD
    a=10; b=5; op=3'b000; #10;

    // SUB
    a=10; b=5; op=3'b001; #10;

    // AND
    a=10; b=5; op=3'b010; #10;

    // OR
    a=10; b=5; op=3'b011; #10;

    // SLT
    a=3; b=8; op=3'b100; #10;

    // XOR
    a=10; b=5; op=3'b101; #10;

    // SHIFT LEFT
    a=10; op=3'b110; #10;

    // SHIFT RIGHT
    a=10; op=3'b111; #10;

    // OVERFLOW CHECK
    a=8'd255; b=8'd1; op=3'b000; #10;

    $finish;
end

endmodule