module alu_tb;

reg [7:0] a, b;
reg [2:0] op;
wire [7:0] result;
wire zero, carry, overflow;

// Instantiate ALU
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
    $dumpfile("alu.vcd");   // waveform output file
    $dumpvars(0, alu_tb);

    // Print values in terminal
    $monitor("time=%0t | a=%0d b=%0d op=%b result=%0d Z=%b C=%b V=%b",
         $time, a, b, op, result, zero, carry, overflow);

    // Test values
    a = 10; b = 5;

    op = 3'b000; #10; // ADD → 15
    op = 3'b001; #10; // SUB → 5
    op = 3'b010; #10; // AND → 0
    op = 3'b011; #10; // OR  → 15
    op = 3'b100; #10; // SLT → 0
    op = 3'b101; #10; // XOR
    op = 3'b110; #10; // SHIFT LEFT
    op = 3'b111; #10; // SHIFT RIGHT

    // Change inputs
    a = 8'd3; b = 8'd8;

    op = 3'b100; #10; // SLT → 1

    a = 8'd255 ; b = 8'd1;
    op = 3'b000; #10;

    a = 8'd128; b = 0;   // 10000000
    op = 3'b110; #10;

    a = 8'd5; b = 0;     // 00000101
    op = 3'b111; #10;

    $finish;
end

endmodule