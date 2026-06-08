module control_unit_tb;

reg [2:0] opcode;
wire we;
wire sel;

control_unit uut (
    .opcode(opcode),
    .we(we),
    .sel(sel)
);

initial begin
    $monitor("opcode=%b | we=%b sel=%b", opcode, we, sel);

    // ADD
    opcode = 3'b000; #10;

    // LOAD
    opcode = 3'b111; #10;

    // default
    opcode = 3'b010; #10;

    $finish;
end

endmodule