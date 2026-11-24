module regfile_tb;

reg clk;
reg we;
reg [2:0] ra1, ra2, wa;
reg [7:0] wd;
wire [7:0] rd1, rd2;

// Instantiate
regfile uut (
    .clk(clk),
    .we(we),
    .ra1(ra1),
    .ra2(ra2),
    .wa(wa),
    .wd(wd),
    .rd1(rd1),
    .rd2(rd2)
);

// Clock generation
always #5 clk = ~clk;

initial begin
    ra1 = 0;
    ra2 = 0;
    $dumpfile("regfile.vcd");
    $dumpvars(0, regfile_tb);

    $monitor("time=%0t | WE=%b WA=%d WD=%d | RA1=%d RD1=%d | RA2=%d RD2=%d",
        $time, we, wa, wd, ra1, rd1, ra2, rd2);

    clk = 0;
    we = 0;

    // Write 10 to R1
    we = 1; wa = 3'd1; wd = 8'd10; #10;

    // Write 20 to R2
    wa = 3'd2; wd = 8'd20; #10;

    // Disable write
    we = 0;

    // Read R1 and R2
    ra1 = 3'd1;
    ra2 = 3'd2;
    #10;

    // Change read addresses
    ra1 = 3'd0;
    ra2 = 3'd1;
    #10;

    $finish;
end

endmodule