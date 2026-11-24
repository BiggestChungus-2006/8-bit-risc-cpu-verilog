`timescale 1ns/1ps

module cpu_comprehensive_tb;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  integer failures = 0;
  integer tests_run = 0;
  integer tests_fail = 0;
  integer wh_cnt = 0;
  integer bt_count = 0;
  reg x_seen = 1'b0;
  reg [63:0] expv = 64'd0;
  integer expwc [0:7];
  integer wcount [0:7];
  integer cur_t = 0;
  integer RUN_N = 0;
  integer bt_exp = 0;
  reg xflag = 1'b0;

  // T8 PC/fetch and branch-target evidence
  reg [3:0]  fetch_pc_log [0:255];
  reg [11:0] fetch_instr_log [0:255];
  integer    fetch_n = 0;
  reg [3:0]  bt_pc_log [0:63];
  integer    bt_next_idx [0:63];
  integer    bt_pc_n = 0;
  reg [3:0]  exp_bt_pc [0:63];
  integer    exp_bt_n = -1;
  integer    t8_case = 0;

  wire [3:0]  pc;
  wire [11:0] instr;
  wire        zero;
  wire        branch_taken;

  cpu dut (
    .clk(clk), .pc(pc), .instr(instr), .zero(zero), .branch_taken(branch_taken)
  );

  reg [11:0] pmem [0:15];
  reg [7:0]  dmem [0:255];

  function [11:0] f_add;
    input [2:0] rd; input [2:0] rs1; input [2:0] rs2;
    begin f_add = {3'b000, rs1, rs2, rd}; end
  endfunction
  function [11:0] f_sub;
    input [2:0] rd; input [2:0] rs1; input [2:0] rs2;
    begin f_sub = {3'b001, rs1, rs2, rd}; end
  endfunction
  function [11:0] f_and;
    input [2:0] rd; input [2:0] rs1; input [2:0] rs2;
    begin f_and = {3'b010, rs1, rs2, rd}; end
  endfunction
  function [11:0] f_or;
    input [2:0] rd; input [2:0] rs1; input [2:0] rs2;
    begin f_or = {3'b011, rs1, rs2, rd}; end
  endfunction
  function [11:0] f_slt;
    input [2:0] rd; input [2:0] rs1; input [2:0] rs2;
    begin f_slt = {3'b100, rs1, rs2, rd}; end
  endfunction
  function [11:0] f_xor;
    input [2:0] rd; input [2:0] rs1; input [2:0] rs2;
    begin f_xor = {3'b101, rs1, rs2, rd}; end
  endfunction
  function [11:0] f_load;
    input [2:0] rd; input [2:0] rs1;
    begin f_load = {3'b111, rs1, 3'b000, rd}; end
  endfunction
  function [11:0] f_beq;
    input [2:0] rs1; input [2:0] rs2; input [2:0] off;
    begin f_beq = {3'b110, rs1, rs2, off}; end
  endfunction

  task clear_dut;
    integer i;
    begin
      dut.pc = 4'd0;
      dut.if_id_instr = 12'd0;
      dut.if_id_pc = 4'd0;
      dut.id_ex_is_branch = 1'b0;
      dut.id_ex_branch_target = 4'd0;
      dut.dp.id_ex_rd1 = 8'd0;
      dut.dp.id_ex_rd2 = 8'd0;
      dut.dp.id_ex_op = 3'd0;
      dut.dp.id_ex_rd = 3'd0;
      dut.dp.id_ex_we = 1'b0;
      dut.dp.id_ex_sel = 1'b0;
      dut.dp.id_ex_rs1 = 3'd0;
      dut.dp.id_ex_rs2 = 3'd0;
      dut.dp.ex_mem_alu_result = 8'd0;
      dut.dp.ex_mem_rd = 3'd0;
      dut.dp.ex_mem_we = 1'b0;
      dut.dp.ex_mem_sel = 1'b0;
      dut.dp.ex_mem_addr = 8'd0;
      dut.dp.mem_wb_wd = 8'd0;
      dut.dp.mem_wb_rd = 3'd0;
      dut.dp.mem_wb_we = 1'b0;
      dut.dp.rf.regs[0] = 8'd0;
      dut.dp.rf.regs[1] = 8'd0;
      dut.dp.rf.regs[2] = 8'd0;
      dut.dp.rf.regs[3] = 8'd0;
      dut.dp.rf.regs[4] = 8'd0;
      dut.dp.rf.regs[5] = 8'd0;
      dut.dp.rf.regs[6] = 8'd0;
      dut.dp.rf.regs[7] = 8'd0;
      for (i=0;i<16;i=i+1) dut.imem.memory[i] = 12'd0;
      for (i=0;i<256;i=i+1) dmem[i] = 8'd0;
      for (i=0;i<8;i=i+1) wcount[i] = 0;
      bt_count = 0;
      x_seen = 1'b0;
      wh_cnt = 0;
      fetch_n = 0;
      bt_pc_n = 0;
      exp_bt_n = -1;
      t8_case = 0;
    end
  endtask

  task do_xcheck;
    begin
      xflag = (^{dut.dp.fwd_id_wb_1, dut.dp.fwd_id_wb_2, dut.dp.fwd_ex_mem_a,
                  dut.dp.fwd_mem_wb_a, dut.dp.fwd_ex_mem_b, dut.dp.fwd_mem_wb_b,
                  branch_taken, zero, dut.dp.a_in, dut.dp.b_in, dut.dp.mem_stage_value,
                  dut.dp.mem_wb_wd, dut.if_id_instr, dut.id_ex_is_branch,
                  dut.id_ex_branch_target, pc, instr});
      if (xflag === 1'bx) x_seen = 1'b1;
    end
  endtask

  task run_cycles;
    integer k;
    reg bt_s;
    reg [3:0] tgt;
    begin
      for (k=0;k<RUN_N;k=k+1) begin
        @(posedge clk);
        fetch_pc_log[fetch_n] = pc;
        fetch_instr_log[fetch_n] = instr;
        fetch_n = fetch_n + 1;
        bt_s = branch_taken;
        if (bt_s === 1'b1) begin
          tgt = dut.id_ex_branch_target;
          bt_pc_log[bt_pc_n] = tgt;
          bt_next_idx[bt_pc_n] = fetch_n;
          bt_pc_n = bt_pc_n + 1;
        end
        #1;
        if (bt_s === 1'b1 && pc !== tgt) begin
          failures = failures + 1;
          $display("FAIL t=%0d C%0d BRANCH_PC=%0d EXP=%0d", cur_t, t8_case, pc, tgt);
        end
        do_xcheck;
      end
    end
  endtask

  task finish_test;
    integer r;
    integer i;
    integer j;
    integer fail_before;
    begin
      fail_before = failures;
      tests_run = tests_run + 1;
      if (dut.dp.rf.regs[0] !== 8'd0) begin
        failures = failures + 1; tests_fail = tests_fail + 1;
        $display("FAIL t=%0d C%0d R0=%0d", cur_t, t8_case, dut.dp.rf.regs[0]);
      end
      for (r=1;r<8;r=r+1) begin
        if (dut.dp.rf.regs[r] !== expv[8*r +: 8]) begin
          failures = failures + 1; tests_fail = tests_fail + 1;
          $display("FAIL t=%0d C%0d R%0d=%0d exp=%0d", cur_t, t8_case, r, dut.dp.rf.regs[r], expv[8*r +: 8]);
        end
      end
      for (i=0;i<8;i=i+1) begin
        if (wcount[i] !== expwc[i]) begin
          failures = failures + 1; tests_fail = tests_fail + 1;
          $display("FAIL t=%0d C%0d WRITES R%0d=%0d exp=%0d", cur_t, t8_case, i, wcount[i], expwc[i]);
        end
      end
      if (bt_count !== bt_exp) begin
        failures = failures + 1; tests_fail = tests_fail + 1;
        $display("FAIL t=%0d C%0d BT=%0d exp=%0d", cur_t, t8_case, bt_count, bt_exp);
      end
      if (x_seen) begin
        failures = failures + 1; tests_fail = tests_fail + 1;
        $display("FAIL t=%0d C%0d X/Z", cur_t, t8_case);
      end
      if (exp_bt_n >= 0) begin
        if (bt_pc_n !== exp_bt_n) begin
          failures = failures + 1; tests_fail = tests_fail + 1;
          $display("FAIL t=%0d C%0d BT_PC_N=%0d exp=%0d", cur_t, t8_case, bt_pc_n, exp_bt_n);
        end
        for (j=0;j<exp_bt_n && j<bt_pc_n;j=j+1) begin
          if (bt_pc_log[j] !== exp_bt_pc[j]) begin
            failures = failures + 1; tests_fail = tests_fail + 1;
            $display("FAIL t=%0d C%0d BT_PC[%0d]=%0d exp=%0d", cur_t, t8_case, j, bt_pc_log[j], exp_bt_pc[j]);
          end
          if (bt_next_idx[j] >= fetch_n || fetch_pc_log[bt_next_idx[j]] !== exp_bt_pc[j]) begin
            failures = failures + 1; tests_fail = tests_fail + 1;
            $display("FAIL t=%0d C%0d FETCH_AFTER_BT[%0d] idx=%0d exp_pc=%0d", cur_t, t8_case, j, bt_next_idx[j], exp_bt_pc[j]);
          end
        end
      end
      if (failures == fail_before)
        $display("PASS t=%0d C%0d", cur_t, t8_case);
      else
        $display("FAILED t=%0d C%0d", cur_t, t8_case);
      if (cur_t == 8 && failures == fail_before) begin
        $display("  T8 C%0d writes R1..R7 = %0d %0d %0d %0d %0d %0d %0d",
                 t8_case, wcount[1], wcount[2], wcount[3], wcount[4],
                 wcount[5], wcount[6], wcount[7]);
        for (j=0;j<bt_pc_n;j=j+1)
          $display("  T8 C%0d bt[%0d] target=%0d next_fetch_pc=%0d",
                   t8_case, j, bt_pc_log[j], fetch_pc_log[bt_next_idx[j]]);
      end
    end
  endtask

  task run_t1;
    begin
      clear_dut;
      cur_t = 1;
      dut.imem.memory[0] = f_load(3'd1, 3'd0);
      dut.imem.memory[1] = f_add (3'd2, 3'd1, 3'd0);
      dut.imem.memory[2] = f_beq(3'd2, 3'd1, 3'b010);
      dut.imem.memory[3] = f_add(3'd3, 3'd0, 3'd0);
      dut.imem.memory[4] = f_add(3'd4, 3'd1, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv = 64'd0;
      expv[8*1 +: 8] = 8'd10;
      expv[8*2 +: 8] = 8'd10;
      expv[8*4 +: 8] = 8'd10;
      expwc[0]=0; expwc[1]=1; expwc[2]=1; expwc[3]=0; expwc[4]=1; expwc[5]=0; expwc[6]=0; expwc[7]=0;
      bt_exp = 1;
      RUN_N = 20;
      run_cycles;
      finish_test;
    end
  endtask

  task run_t2;
    begin
      clear_dut;
      cur_t = 2;
      dut.imem.memory[0] = f_load(3'd1, 3'd0);
      dut.imem.memory[1] = f_add (3'd2, 3'd1, 3'd0);
      dut.imem.memory[2] = f_add(3'd0, 3'd0, 3'd0);
      dut.imem.memory[3] = f_add(3'd0, 3'd0, 3'd0);
      dut.imem.memory[4] = f_beq(3'd1, 3'd2, 3'b010);
      dut.imem.memory[5] = f_add(3'd3, 3'd0, 3'd0);
      dut.imem.memory[6] = f_add(3'd4, 3'd2, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv = 64'd0;
      expv[8*1 +: 8] = 8'd10;
      expv[8*2 +: 8] = 8'd10;
      expv[8*4 +: 8] = 8'd10;
      expwc[0]=0; expwc[1]=1; expwc[2]=1; expwc[3]=0; expwc[4]=1; expwc[5]=0; expwc[6]=0; expwc[7]=0;
      bt_exp = 1;
      RUN_N = 20;
      run_cycles;
      finish_test;
    end
  endtask

  task run_t3;
    begin
      clear_dut;
      cur_t = 3;
      dut.imem.memory[0] = f_load(3'd1, 3'd0);
      dut.imem.memory[1] = f_add (3'd2, 3'd1, 3'd0);
      dut.imem.memory[2] = f_beq(3'd2, 3'd0, 3'b010);
      dut.imem.memory[3] = f_add(3'd3, 3'd1, 3'd0);
      dut.imem.memory[4] = f_add(3'd4, 3'd0, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv = 64'd0;
      expv[8*1 +: 8] = 8'd10;
      expv[8*2 +: 8] = 8'd10;
      expv[8*3 +: 8] = 8'd10;
      expv[8*4 +: 8] = 8'd0;
      expwc[0]=0; expwc[1]=1; expwc[2]=1; expwc[3]=1; expwc[4]=1; expwc[5]=0; expwc[6]=0; expwc[7]=0;
      bt_exp = 0;
      RUN_N = 20;
      run_cycles;
      finish_test;
    end
  endtask

  task run_t4;
    begin
      clear_dut;
      cur_t = 4;
      dut.imem.memory[0] = f_load(3'd1, 3'd0);
      dut.imem.memory[1] = f_beq(3'd0, 3'd0, 3'b001);
      dut.imem.memory[2] = f_add(3'd5, 3'd1, 3'd0);
      expv = 64'd0;
      expv[8*1 +: 8] = 8'd10;
      expv[8*5 +: 8] = 8'd10;
      expwc[0]=0; expwc[1]=1; expwc[2]=0; expwc[3]=0; expwc[4]=0; expwc[5]=1; expwc[6]=0; expwc[7]=0;
      bt_exp = 1;
      RUN_N = 20;
      run_cycles;
      finish_test;
    end
  endtask

  task run_t5;
    begin
      clear_dut;
      cur_t = 5;
      dut.imem.memory[0] = f_load(3'd1, 3'd0);
      dut.imem.memory[1] = f_add(3'd0, 3'd0, 3'd0);
      dut.imem.memory[2] = f_load(3'd2, 3'd1);
      dut.dp.dm.memory[0] = 8'd10;
      dut.dp.dm.memory[10] = 8'd42;
      expv = 64'd0;
      expv[8*1 +: 8] = 8'd10;
      expv[8*2 +: 8] = 8'd42;
      expwc[0]=0; expwc[1]=1; expwc[2]=1; expwc[3]=0; expwc[4]=0; expwc[5]=0; expwc[6]=0; expwc[7]=0;
      bt_exp = 0;
      RUN_N = 20;
      run_cycles;
      finish_test;
    end
  endtask

  task run_t6;
    begin
      clear_dut;
      cur_t = 6;
      dut.imem.memory[0] = f_load(3'd1, 3'd0);
      dut.imem.memory[1] = f_add (3'd2, 3'd1, 3'd0);
      dut.imem.memory[2] = f_beq(3'd2, 3'd1, 3'b011);
      dut.imem.memory[3] = f_add(3'd3, 3'd0, 3'd0);
      dut.imem.memory[4] = f_add(3'd4, 3'd0, 3'd0);
      dut.imem.memory[5] = f_add(3'd5, 3'd2, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv = 64'd0;
      expv[8*1 +: 8] = 8'd10;
      expv[8*2 +: 8] = 8'd10;
      expv[8*5 +: 8] = 8'd10;
      expwc[0]=0; expwc[1]=1; expwc[2]=1; expwc[3]=0; expwc[4]=0; expwc[5]=1; expwc[6]=0; expwc[7]=0;
      bt_exp = 1;
      RUN_N = 20;
      run_cycles;
      finish_test;
    end
  endtask

  task run_t7;
    begin
      clear_dut;
      cur_t = 7;
      dut.imem.memory[0] = f_load(3'd1, 3'd0);
      dut.imem.memory[1] = f_add (3'd2, 3'd1, 3'd1);
      dut.imem.memory[2] = f_beq(3'd2, 3'd1, 3'b010);
      dut.imem.memory[3] = f_add(3'd3, 3'd2, 3'd0);
      dut.imem.memory[4] = f_add(3'd4, 3'd0, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv = 64'd0;
      expv[8*1 +: 8] = 8'd10;
      expv[8*2 +: 8] = 8'd20;
      expv[8*3 +: 8] = 8'd20;
      expv[8*4 +: 8] = 8'd0;
      expwc[0]=0; expwc[1]=1; expwc[2]=1; expwc[3]=1; expwc[4]=1; expwc[5]=0; expwc[6]=0; expwc[7]=0;
      bt_exp = 0;
      RUN_N = 20;
      run_cycles;
      finish_test;
    end
  endtask

  // T8: branch-offset and PC-wraparound checks.  Each case is a small
  // directed program using BEQ R0,R0 so the branch is unconditionally taken;
  // this isolates offset/target/PC behaviour from operand forwarding, which
  // T1-T7 already cover.  At every taken-branch edge the testbench records
  // dut.id_ex_branch_target and checks (a) pc becomes that value and (b) the
  // next fetch in fetch_pc_log is the same PC.  Wrong-path markers use
  // distinct destination registers and are checked with wcount.
  task t8_prepare;
    input integer c;
    begin
      clear_dut;
      cur_t = 8;
      t8_case = c;
      expv = 64'd0;
      expwc[0]=0; expwc[1]=0; expwc[2]=0; expwc[3]=0;
      expwc[4]=0; expwc[5]=0; expwc[6]=0; expwc[7]=0;
      bt_exp = 0;
      exp_bt_n = 0;
    end
  endtask

  task run_t8;
    integer k;
    begin
      // ---- T8 C1: offset +1, branch at PC0 -> target PC1 ----
      // BEQ R0,R0,+1 is taken.  PC1 is initially fetched as wrong-path,
      // must be flushed, then re-fetched as the real target and commit once.
      t8_prepare(1);
      dut.imem.memory[0] = f_beq(3'd0, 3'd0, 3'b001);
      dut.imem.memory[1] = f_load(3'd5, 3'd0);
      dut.imem.memory[2] = f_add(3'd6, 3'd0, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*5 +: 8] = 8'd10;
      expwc[5] = 1; expwc[6] = 1;
      bt_exp = 1;
      exp_bt_pc[0] = 4'd1; exp_bt_n = 1;
      RUN_N = 20;
      run_cycles;
      finish_test;

      // ---- T8 C2: offset +2, branch at PC0 -> target PC2 ----
      // PC1 is wrong-path only.  PC2 is wrong-path and target; it must
      // commit exactly once (the flush must remove the first fetch).
      t8_prepare(2);
      dut.imem.memory[0] = f_beq(3'd0, 3'd0, 3'b010);
      dut.imem.memory[1] = f_add(3'd5, 3'd0, 3'd0);
      dut.imem.memory[2] = f_load(3'd6, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*6 +: 8] = 8'd10;
      expwc[6] = 1;
      bt_exp = 1;
      exp_bt_pc[0] = 4'd2; exp_bt_n = 1;
      RUN_N = 19;
      run_cycles;
      finish_test;

      // ---- T8 C3: offset +3, branch at PC0 -> target PC3 ----
      // Both younger instructions (PC1, PC2) are wrong-path and must not write.
      t8_prepare(3);
      dut.imem.memory[0] = f_beq(3'd0, 3'd0, 3'b011);
      dut.imem.memory[1] = f_add(3'd5, 3'd0, 3'd0);
      dut.imem.memory[2] = f_add(3'd6, 3'd0, 3'd0);
      dut.imem.memory[3] = f_load(3'd7, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*7 +: 8] = 8'd10;
      expwc[7] = 1;
      bt_exp = 1;
      exp_bt_pc[0] = 4'd3; exp_bt_n = 1;
      RUN_N = 18;
      run_cycles;
      finish_test;

      // ---- T8 C4: offset -1, branch at PC0 -> target PC15 (0-1 wrap) ----
      // The loop is bounded by RUN_N.  Each taken branch must redirect to 15;
      // the target LOAD is older than the next branch and must keep committing.
      t8_prepare(4);
      dut.imem.memory[0] = f_beq(3'd0, 3'd0, 3'b111);
      dut.imem.memory[1] = f_add(3'd5, 3'd0, 3'd0);
      dut.imem.memory[2] = f_add(3'd6, 3'd0, 3'd0);
      dut.imem.memory[15] = f_load(3'd7, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*7 +: 8] = 8'd10;
      expwc[7] = 4;
      bt_exp = 5;
      exp_bt_n = 5;
      for (k=0;k<5;k=k+1) exp_bt_pc[k] = 4'd15;
      RUN_N = 20;
      run_cycles;
      finish_test;

      // ---- T8 C5: offset -2, branch at PC8 -> target PC6 ----
      t8_prepare(5);
      dut.imem.memory[6] = f_load(3'd7, 3'd0);
      dut.imem.memory[8] = f_beq(3'd0, 3'd0, 3'b110);
      dut.imem.memory[9] = f_add(3'd5, 3'd0, 3'd0);
      dut.imem.memory[10] = f_add(3'd6, 3'd0, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*7 +: 8] = 8'd10;
      expwc[7] = 3;
      bt_exp = 3;
      exp_bt_n = 3;
      for (k=0;k<3;k=k+1) exp_bt_pc[k] = 4'd6;
      RUN_N = 22;
      run_cycles;
      finish_test;

      // ---- T8 C6: offset -3, branch at PC8 -> target PC5 ----
      t8_prepare(6);
      dut.imem.memory[5] = f_load(3'd7, 3'd0);
      dut.imem.memory[8] = f_beq(3'd0, 3'd0, 3'b101);
      dut.imem.memory[9] = f_add(3'd5, 3'd0, 3'd0);
      dut.imem.memory[10] = f_add(3'd6, 3'd0, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*7 +: 8] = 8'd10;
      expwc[7] = 3;
      bt_exp = 3;
      exp_bt_n = 3;
      for (k=0;k<3;k=k+1) exp_bt_pc[k] = 4'd5;
      RUN_N = 24;
      run_cycles;
      finish_test;

      // ---- T8 C7: offset -4, branch at PC8 -> target PC4 ----
      t8_prepare(7);
      dut.imem.memory[4] = f_load(3'd7, 3'd0);
      dut.imem.memory[8] = f_beq(3'd0, 3'd0, 3'b100);
      dut.imem.memory[9] = f_add(3'd5, 3'd0, 3'd0);
      dut.imem.memory[10] = f_add(3'd6, 3'd0, 3'd0);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*7 +: 8] = 8'd10;
      expwc[7] = 3;
      bt_exp = 3;
      exp_bt_n = 3;
      for (k=0;k<3;k=k+1) exp_bt_pc[k] = 4'd4;
      RUN_N = 26;
      run_cycles;
      finish_test;

      // ---- T8 C8: branch at PC15, offset +1 -> target PC0 (15-0 wrap) ----
      // PC14 is an older valid instruction already in the pipeline when the
      // branch resolves; it must still commit.  PC0/PC1 are wrong-path copies
      // that must be flushed before their correct-path re-fetch.
      t8_prepare(8);
      dut.imem.memory[0] = f_load(3'd7, 3'd0);
      dut.imem.memory[1] = f_add(3'd5, 3'd0, 3'd0);
      dut.imem.memory[14] = f_add(3'd6, 3'd0, 3'd0);
      dut.imem.memory[15] = f_beq(3'd0, 3'd0, 3'b001);
      dut.dp.dm.memory[0] = 8'd10;
      expv[8*7 +: 8] = 8'd10;
      expwc[5] = 2; expwc[6] = 1; expwc[7] = 2;
      bt_exp = 1;
      exp_bt_pc[0] = 4'd0; exp_bt_n = 1;
      RUN_N = 24;
      run_cycles;
      finish_test;
    end
  endtask

  always @(posedge clk) begin
    if (dut.dp.mem_wb_we === 1'b1 && dut.dp.mem_wb_rd !== 3'd0) begin
      wcount[dut.dp.mem_wb_rd] = wcount[dut.dp.mem_wb_rd] + 1;
    end
    if (branch_taken === 1'b1) bt_count = bt_count + 1;
  end

  initial begin
    #100000;
    $display("FAIL: watchdog timeout");
    $finish;
  end

  initial begin
    clear_dut;
    run_t1;
    run_t2;
    run_t3;
    run_t4;
    run_t5;
    run_t6;
    run_t7;
    run_t8;
    if (failures == 0)
      $display("ALL COMPREHENSIVE TESTS PASSED");
    else
      $display("COMPREHENSIVE TESTS FAILED: %0d", failures);
    $finish;
  end

endmodule
