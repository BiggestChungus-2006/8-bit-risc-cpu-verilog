module datapath_tb;

reg clk;
reg we;
reg sel;
reg [7:0] ext_data;
reg [11:0] instr;

datapath uut (
    .clk(clk),
    .we(we),
    .ext_data(ext_data),
    .sel(sel),
    .instr(instr)
);
// Clock generator
always #5 clk = ~clk;




initial begin
    $dumpfile("datapath.vcd");
    $dumpvars(0, datapath_tb);

    $monitor("t=%0t | WE=%b SEL=%b | INSTR=%b | RD1=%d RD2=%d | WD=%d | ALU_OUT=%d",
         $time, we, sel, instr, uut.rd1, uut.rd2, uut.wd, uut.alu_result);

    // Initialize
    clk = 0;
    we = 0;
    sel = 0;
    ext_data = 0;
    instr = 0;

    #1;

    // 🔥 STEP 1: Load R1 = 10
    we = 1;
    sel = 1;
    instr = 12'b000_000_000_001; // rd = 1
    ext_data = 8'd10;
    #10;

    // 🔥 STEP 2: Load R2 = 5
    instr = 12'b000_000_000_010; // rd = 2
    ext_data = 8'd5;
    #10;

    // 🔥 STEP 3: ADD R1, R2 → R3
    sel = 0;
    we = 1;
    instr = 12'b000_001_010_011; // ADD
    #10;

    // 🔥 STEP 4: Observe result (R3)
    we = 0;
    instr = 12'b000_011_000_000; // route R3
    #10;

    $finish;
end

endmodule