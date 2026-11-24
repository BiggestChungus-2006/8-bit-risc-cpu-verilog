`timescale 1ns/1ps

// ============================================================================
// cpu_tb.v - self-checking system-level testbench for the 5-stage CPU
//
// HOW IT WORKS
//   The CPU has no reset input, so every test gets its own CPU instance
//   (generate loop below). Each instance is loaded with its own program through
//   a hierarchical write into its instr_mem at t = 1, before the first clock
//   edge (first rising edge is at t = 5). Test 0 is not overwritten: it runs the
//   program built into instr_mem.v.
//
//   Tests 12-30 verify SUB, AND, OR, SLT and XOR (tests 0-11 are unchanged).
//   Because the ISA has no immediates, each of these instances also gets its
//   DATA memory preloaded by hierarchical write (dut.dp.dm.memory) at t = 1:
//   DMEM[0]=1, DMEM[1]=2, DMEM[2]=A, DMEM[A]=B, so that four LOADs give
//   R1=1, R2=2, R3=A, R4=B. The ALU operations then read R3, R4 and R0.
//     12-24  group A: isolated ALU tests (operands come from the register file)
//     25     group D: one operand pair through all five ops (opcode discrimination)
//     26-27  group B: forwarded operands
//     28-30  group C: result chains (non-ADD results forwarded into later ops)
//   SLT is unsigned; all arithmetic wraps modulo 256.
//
//   All instances run in lock-step and are checked once, just after rising
//   edge CHECK_EDGE (= 16). The 4-bit PC wraps 15 -> 0 after 16 fetches, so a
//   straight-line program would start re-executing from edge 17. Checking at
//   edge 16 therefore always happens BEFORE any re-executed instruction can
//   change state. A guard additionally fails the test if the wrapped fetch
//   was ever observed before the check.
//
// WHAT EACH TEST CHECKS (exact, not just "R1 and R2")
//   1. the final value of every register R1..R7 (unlisted registers must be 0,
//      so any stray / wrong-path write is caught) and R0 == 0
//   2. the SET of registers that were ever written back (catches a wrong-path
//      write even if the value written happens to equal the expected value)
//   3. the number of cycles in which branch_taken was asserted
//   4. no X/Z on any forwarding control signal, branch_taken, zero or the
//      forwarded ALU operands at any time from t = 2 onward
//
// Failure => $fatal. Success prints one [PASS] line per test and a final message.
// Waveforms: cpu.vcd, e.g. scope cpu_tb.t[6].dut.dp for the taken-BEQ test.
// ============================================================================
module cpu_tb;

    localparam NUM_TESTS  = 31;      // tests 0-11: original, 12-30: ALU instruction tests
    localparam FIRST_ALU_TEST = 12;
    localparam CHECK_EDGE = 16;      // see header: must stay <= 16 (PC wrap)

    reg     clk      = 1'b0;
    integer failures = 0;

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Instruction encoding helpers  [11:9]=op [8:6]=rs1 [5:3]=rs2 [2:0]=rd
    // ------------------------------------------------------------------
    localparam [2:0] OP_ADD = 3'b000, OP_BEQ = 3'b110, OP_LOAD = 3'b111;
    localparam [2:0] OP_SUB = 3'b001, OP_AND = 3'b010, OP_OR  = 3'b011,
                     OP_SLT = 3'b100, OP_XOR = 3'b101;
    localparam [2:0] R0 = 3'd0, R1 = 3'd1, R2 = 3'd2, R3 = 3'd3,
                     R4 = 3'd4, R5 = 3'd5, R6 = 3'd6, R7 = 3'd7;
    localparam [2:0] OFF_P2 = 3'b010,   // +2
                     OFF_P3 = 3'b011,   // +3
                     OFF_M2 = 3'b110;   // -2
    localparam [11:0] NOP = 12'b000_000_000_000;   // ADD R0,R0,R0

    function [11:0] i_add(input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        i_add = {OP_ADD, rs1, rs2, rd};
    endfunction

    function [11:0] i_sub(input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        i_sub = {OP_SUB, rs1, rs2, rd};
    endfunction

    function [11:0] i_and(input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        i_and = {OP_AND, rs1, rs2, rd};
    endfunction

    function [11:0] i_or(input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        i_or = {OP_OR, rs1, rs2, rd};
    endfunction

    function [11:0] i_slt(input [2:0] rd, input [2:0] rs1, input [2:0] rs2);   // unsigned a < b
        i_slt = {OP_SLT, rs1, rs2, rd};
    endfunction

    function [11:0] i_xor(input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        i_xor = {OP_XOR, rs1, rs2, rd};
    endfunction

    function [11:0] i_load(input [2:0] rd, input [2:0] rs1);   // R[rd] = DMEM[R[rs1]]
        i_load = {OP_LOAD, rs1, 3'b000, rd};
    endfunction

    function [11:0] i_beq(input [2:0] rs1, input [2:0] rs2, input [2:0] off);
        i_beq = {OP_BEQ, rs1, rs2, off};
    endfunction

    // ------------------------------------------------------------------
    // Test programs (unlisted addresses are NOPs). DMEM[0]=10, DMEM[10]=42.
    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    // Operand fixture for the ALU tests (tests >= FIRST_ALU_TEST).
    // The ISA has no immediates and no STORE, so operands come from a pointer
    // chain through data memory (preloaded per instance, see the generate block):
    //     DMEM[0] = 1,  DMEM[1] = 2,  DMEM[2] = A,  DMEM[A] = B
    //     LOAD R1,[R0] -> 1 ; LOAD R2,[R1] -> 2 ; LOAD R3,[R2] -> A ; LOAD R4,[R3] -> B
    // A must not be 0, 1 or 2 (address collision); a zero operand is taken from R0.
    // ------------------------------------------------------------------
    function [11:0] alu_fixture(input integer a);
        begin
            case (a)
            0: alu_fixture = i_load(R1, R0);
            1: alu_fixture = i_load(R2, R1);
            2: alu_fixture = i_load(R3, R2);
            3: alu_fixture = i_load(R4, R3);
            default: alu_fixture = NOP;
            endcase
        end
    endfunction

    // Operand values: A is loaded into R3, B into R4.
    function [7:0] op_a(input integer tid);
        begin
            case (tid)
            12: op_a = 42;
            13: op_a = 128;
            14: op_a = 255;
            15: op_a = 204;
            16: op_a = 240;
            17: op_a = 255;
            18: op_a = 240;
            19: op_a = 204;
            20: op_a = 204;
            21: op_a = 170;
            22: op_a = 10;
            23: op_a = 127;
            24: op_a = 255;
            25: op_a = 170;
            26: op_a = 204;
            27: op_a = 170;
            28: op_a = 170;
            29: op_a = 10;
            30: op_a = 10;
            default: op_a = 8'd0;
            endcase
        end
    endfunction

    function [7:0] op_b(input integer tid);
        begin
            case (tid)
            12: op_b = 10;
            13: op_b = 127;
            14: op_b = 255;
            15: op_b = 170;
            16: op_b = 15;
            17: op_b = 255;
            18: op_b = 15;
            19: op_b = 170;
            20: op_b = 170;
            21: op_b = 85;
            22: op_b = 42;
            23: op_b = 128;
            24: op_b = 0;
            25: op_b = 204;
            26: op_b = 170;
            27: op_b = 204;
            28: op_b = 204;
            29: op_b = 42;
            30: op_b = 42;
            default: op_b = 8'd0;
            endcase
        end
    endfunction

    function [11:0] prog(input integer tid, input integer a);
        begin
            prog = NOP;
            case (tid)
            // 1: LOAD -> ADD            R1=10, R2=20
            1: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_add (R2, R1, R1);
               endcase
            // 2: ADD -> ADD chain       R1=10 R2=20 R3=30 R4=50
            //    I2 reads R2 from EX/MEM and R1 from MEM/WB; I3 reads R3 (EX/MEM) and R2 (MEM/WB)
            2: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_add (R2, R1, R1);
                2: prog = i_add (R3, R2, R1);
                3: prog = i_add (R4, R3, R2);
               endcase
            // 3: ALU -> LOAD address    R1=10 R2=42 R3=10 R4=10 R5=42
            3: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_add (R4, R1, R0);   // R4 = 10
                2: prog = i_load(R5, R4);       // address from the previous ALU result (distance 1)
                3: prog = i_add (R3, R1, R0);   // R3 = 10
                4: prog = NOP;
                5: prog = i_load(R2, R3);       // address from an ALU result 2 instructions earlier
               endcase
            // 4: same-destination priority   R1=10 R6=30 R7=30
            //    I3 sees R6 in both EX/MEM (30, newest) and MEM/WB (20, older): must take 30
            4: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_add (R6, R1, R1);   // R6 = 20
                2: prog = i_add (R6, R6, R1);   // R6 = 30
                3: prog = i_add (R7, R6, R0);   // R7 must be 30
               endcase
            // 5: R0 protection          R1=10 R3=10 R4=0 R5=10, R0 stays 0
            5: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_add (R0, R1, R1);   // attempted write of 20 to R0
                2: prog = i_add (R3, R0, R1);   // must be 0 + 10
                3: prog = i_add (R4, R0, R0);   // must be 0
                4: prog = i_load(R0, R0);       // attempted LOAD into R0 (would be 10)
                5: prog = i_add (R5, R0, R1);   // must be 0 + 10
               endcase
            // 6: taken BEQ, operand from a LOAD (distance 1)    R1=10 R4=20
            //    target = 1 + 3 = 4; I2 (in ID) and I3 (in IF) are wrong-path
            6: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_beq (R1, R1, OFF_P3);
                2: prog = i_add (R2, R1, R1);   // wrong path: R2 must stay 0
                3: prog = i_load(R3, R0);       // wrong path: R3 must stay 0
                4: prog = i_add (R4, R1, R1);   // branch target
               endcase
            // 7: not-taken BEQ          R1=10 R2=20 R3=20 R4=40, no flush
            7: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_beq (R1, R0, OFF_P3);   // 10 != 0
                2: prog = i_add (R2, R1, R1);
                3: prog = i_add (R3, R1, R1);
                4: prog = i_add (R4, R2, R3);
               endcase
            // 8: backward BEQ           R4=10 R5=20 ; 3 taken branches
            //    0 -> 3 ; 3 -> 1 (backward, -2) ; 2 -> 5
            //    The wrong-path BEQ at 3 (after the branch at 2) must be flushed,
            //    otherwise it would loop back to 1 and R5 would never be written.
            8: case (a)
                0: prog = i_beq (R0, R0, OFF_P3);
                1: prog = i_load(R4, R0);
                2: prog = i_beq (R0, R0, OFF_P3);
                3: prog = i_beq (R0, R0, OFF_M2);
                4: prog = i_add (R6, R4, R4);   // wrong path: R6 must stay 0
                5: prog = i_add (R5, R4, R4);
               endcase
            // 9: wrong-path LOAD in ID + wrong-path ADD in IF; BEQ operand from an ALU result
            //    R1=10 R5=20 R4=30 ; R2 and R3 must stay 0
            9: case (a)
                0: prog = i_load(R1, R0);
                1: prog = i_add (R5, R1, R1);
                2: prog = i_beq (R5, R5, OFF_P3);   // target 5
                3: prog = i_load(R2, R0);           // wrong path (ID)
                4: prog = i_add (R3, R1, R1);       // wrong path (IF)
                5: prog = i_add (R4, R5, R1);
               endcase
            // 10: start-up: the very first instructions read non-R0 registers
            10: case (a)
                0: prog = i_add (R3, R2, R2);
                1: prog = i_add (R4, R3, R3);
               endcase
            // 11: LOAD from an address that was never written   R3 must be 0, not X
            11: case (a)
                0: prog = i_load(R1, R0);           // 10
                1: prog = i_add (R2, R1, R1);       // 20
                2: prog = i_load(R3, R2);           // DMEM[20] = 0
                3: prog = i_add (R4, R3, R1);       // 0 + 10
               endcase

            // ---- Group A: isolated ALU tests (3 NOPs after the loads: operands come from the register file) ----
            // 12: SUB: normal / wrap / zero (42,10)   R3 = A = 42, R4 = B = 10
            12: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_sub(R5, R3, R4);   // R5 = SUB(42, 10) = 32
                8: prog = i_sub(R6, R4, R3);   // R6 = SUB(10, 42) = 224
                9: prog = i_sub(R7, R3, R3);   // R7 = SUB(42, 42) = 0
                endcase
            end
            // 13: SUB: boundaries (128,127), R0 operand   R3 = A = 128, R4 = B = 127
            13: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_sub(R5, R3, R4);   // R5 = SUB(128, 127) = 1
                8: prog = i_sub(R6, R4, R3);   // R6 = SUB(127, 128) = 255
                9: prog = i_sub(R7, R0, R4);   // R7 = SUB(0, 127) = 129
                endcase
            end
            // 14: SUB: equal 255,255 / R0 operands   R3 = A = 255, R4 = B = 255
            14: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_sub(R5, R3, R4);   // R5 = SUB(255, 255) = 0
                8: prog = i_sub(R6, R3, R0);   // R6 = SUB(255, 0) = 255
                9: prog = i_sub(R7, R0, R3);   // R7 = SUB(0, 255) = 1
                endcase
            end
            // 15: AND: normal / idempotent / R0 (204,170)   R3 = A = 204, R4 = B = 170
            15: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_and(R5, R3, R4);   // R5 = AND(204, 170) = 136
                8: prog = i_and(R6, R3, R3);   // R6 = AND(204, 204) = 204
                9: prog = i_and(R7, R3, R0);   // R7 = AND(204, 0) = 0
                endcase
            end
            // 16: AND: zero result (240,15)   R3 = A = 240, R4 = B = 15
            16: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_and(R5, R3, R4);   // R5 = AND(240, 15) = 0
                8: prog = i_and(R6, R4, R4);   // R6 = AND(15, 15) = 15
                9: prog = i_and(R7, R4, R3);   // R7 = AND(15, 240) = 0
                endcase
            end
            // 17: AND: all bits set (255,255)   R3 = A = 255, R4 = B = 255
            17: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_and(R5, R3, R4);   // R5 = AND(255, 255) = 255
                8: prog = i_and(R6, R3, R0);   // R6 = AND(255, 0) = 0
                9: prog = i_and(R7, R4, R3);   // R7 = AND(255, 255) = 255
                endcase
            end
            // 18: OR: all ones (240,15)   R3 = A = 240, R4 = B = 15
            18: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_or(R5, R3, R4);   // R5 = OR(240, 15) = 255
                8: prog = i_or(R6, R3, R0);   // R6 = OR(240, 0) = 240
                9: prog = i_or(R7, R4, R4);   // R7 = OR(15, 15) = 15
                endcase
            end
            // 19: OR: normal / R0 operand (204,170)   R3 = A = 204, R4 = B = 170
            19: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_or(R5, R3, R4);   // R5 = OR(204, 170) = 238
                8: prog = i_or(R6, R0, R4);   // R6 = OR(0, 170) = 170
                9: prog = i_or(R7, R0, R0);   // R7 = OR(0, 0) = 0
                endcase
            end
            // 20: XOR: normal / equal -> 0 (204,170)   R3 = A = 204, R4 = B = 170
            20: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_xor(R5, R3, R4);   // R5 = XOR(204, 170) = 102
                8: prog = i_xor(R6, R3, R3);   // R6 = XOR(204, 204) = 0
                9: prog = i_xor(R7, R3, R0);   // R7 = XOR(204, 0) = 204
                endcase
            end
            // 21: XOR: complementary (170,85)   R3 = A = 170, R4 = B = 85
            21: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_xor(R5, R3, R4);   // R5 = XOR(170, 85) = 255
                8: prog = i_xor(R6, R4, R3);   // R6 = XOR(85, 170) = 255
                9: prog = i_xor(R7, R4, R0);   // R7 = XOR(85, 0) = 85
                endcase
            end
            // 22: SLT: basic / reverse / equal (10,42)   R3 = A = 10, R4 = B = 42
            22: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_slt(R5, R3, R4);   // R5 = SLT(10, 42) = 1
                8: prog = i_slt(R6, R4, R3);   // R6 = SLT(42, 10) = 0
                9: prog = i_slt(R7, R3, R3);   // R7 = SLT(10, 10) = 0
                endcase
            end
            // 23: SLT: 127 vs 128 boundary (unsigned)   R3 = A = 127, R4 = B = 128
            23: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_slt(R5, R3, R4);   // R5 = SLT(127, 128) = 1
                8: prog = i_slt(R6, R4, R3);   // R6 = SLT(128, 127) = 0
                9: prog = i_slt(R7, R0, R4);   // R7 = SLT(0, 128) = 1
                endcase
            end
            // 24: SLT: 255 vs 0 boundary (unsigned)   R3 = A = 255, R4 = B = 0
            24: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_slt(R5, R3, R4);   // R5 = SLT(255, 0) = 0
                8: prog = i_slt(R6, R4, R3);   // R6 = SLT(0, 255) = 1
                9: prog = i_slt(R7, R3, R0);   // R7 = SLT(255, 0) = 0
                endcase
            end
            // ---- Group D: opcode discrimination (one operand pair through SUB, AND, OR, XOR, SLT) ----
            // 25: ALL OPS discriminate (170,204)   R3 = A = 170, R4 = B = 204
            25: begin
                prog = alu_fixture(a);
                case (a)
                7: prog = i_sub(R5, R3, R4);   // R5 = SUB(170, 204) = 222
                8: prog = i_and(R6, R3, R4);   // R6 = AND(170, 204) = 136
                9: prog = i_or(R7, R3, R4);   // R7 = OR(170, 204) = 238
                10: prog = i_xor(R1, R3, R4);   // R1 = XOR(170, 204) = 102
                11: prog = i_slt(R2, R3, R4);   // R2 = SLT(170, 204) = 1
                endcase
            end
            // ---- Group B: forwarded operands (ops directly after the loads, forwarding distances 1-4) ----
            // 26: Forwarded operands mix 1 (204,170)   R3 = A = 204, R4 = B = 170
            26: begin
                prog = alu_fixture(a);
                case (a)
                4: prog = i_xor(R5, R3, R4);   // R5 = XOR(204, 170) = 102
                5: prog = i_and(R6, R3, R4);   // R6 = AND(204, 170) = 136
                6: prog = i_sub(R7, R3, R4);   // R7 = SUB(204, 170) = 34
                endcase
            end
            // 27: Forwarded operands mix 2 (170,204)   R3 = A = 170, R4 = B = 204
            27: begin
                prog = alu_fixture(a);
                case (a)
                4: prog = i_or(R5, R3, R4);   // R5 = OR(170, 204) = 238
                5: prog = i_slt(R6, R3, R4);   // R6 = SLT(170, 204) = 1
                6: prog = i_slt(R7, R4, R3);   // R7 = SLT(204, 170) = 0
                endcase
            end
            // ---- Group C: result chains (a non-ADD result is forwarded into the next operation) ----
            // 28: Chain: XOR round trip (170,204)   R3 = A = 170, R4 = B = 204
            28: begin
                prog = alu_fixture(a);
                case (a)
                4: prog = i_xor(R5, R3, R4);   // R5 = XOR(170, 204) = 102
                5: prog = i_xor(R6, R5, R4);   // R6 = XOR(102, 204) = 170
                6: prog = i_sub(R7, R6, R3);   // R7 = SUB(170, 170) = 0
                endcase
            end
            // 29: Chain: SUB wrap round trip (10,42)   R3 = A = 10, R4 = B = 42
            29: begin
                prog = alu_fixture(a);
                case (a)
                4: prog = i_sub(R5, R3, R4);   // R5 = SUB(10, 42) = 224
                5: prog = i_add(R6, R5, R4);   // R6 = ADD(224, 42) = 10
                6: prog = i_slt(R7, R3, R5);   // R7 = SLT(10, 224) = 1
                endcase
            end
            // 30: Chain: SLT -> SUB -> AND (10,42)   R3 = A = 10, R4 = B = 42
            30: begin
                prog = alu_fixture(a);
                case (a)
                4: prog = i_slt(R5, R3, R4);   // R5 = SLT(10, 42) = 1
                5: prog = i_sub(R6, R0, R5);   // R6 = SUB(0, 1) = 255
                6: prog = i_and(R7, R6, R4);   // R7 = AND(255, 42) = 42
                endcase
            end
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // Expected results. Register slot r lives at v[8*r +: 8]; R0 is slot 0.
    // ------------------------------------------------------------------
    function [63:0] exp_regs(input integer tid);
        reg [63:0] v;
        begin
            v = 64'd0;
            case (tid)
            0:  begin v[8*1+:8] = 10; v[8*2+:8] = 42; end
            1:  begin v[8*1+:8] = 10; v[8*2+:8] = 20; end
            2:  begin v[8*1+:8] = 10; v[8*2+:8] = 20; v[8*3+:8] = 30; v[8*4+:8] = 50; end
            3:  begin v[8*1+:8] = 10; v[8*2+:8] = 42; v[8*3+:8] = 10; v[8*4+:8] = 10; v[8*5+:8] = 42; end
            4:  begin v[8*1+:8] = 10; v[8*6+:8] = 30; v[8*7+:8] = 30; end
            5:  begin v[8*1+:8] = 10; v[8*3+:8] = 10; v[8*4+:8] = 0;  v[8*5+:8] = 10; end
            6:  begin v[8*1+:8] = 10; v[8*4+:8] = 20; end
            7:  begin v[8*1+:8] = 10; v[8*2+:8] = 20; v[8*3+:8] = 20; v[8*4+:8] = 40; end
            8:  begin v[8*4+:8] = 10; v[8*5+:8] = 20; end
            9:  begin v[8*1+:8] = 10; v[8*5+:8] = 20; v[8*4+:8] = 30; end
            10: begin v[8*3+:8] = 0;  v[8*4+:8] = 0;  end
            11: begin v[8*1+:8] = 10; v[8*2+:8] = 20; v[8*3+:8] = 0;  v[8*4+:8] = 10; end
            // tests 12-30: R1..R4 from the pointer-chain fixture, R5..R7 (and R1/R2 in test 25) results
            12: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 42; v[8*4+:8] = 10; v[8*5+:8] = 32; v[8*6+:8] = 224; v[8*7+:8] = 0; end
            13: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 128; v[8*4+:8] = 127; v[8*5+:8] = 1; v[8*6+:8] = 255; v[8*7+:8] = 129; end
            14: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 255; v[8*4+:8] = 255; v[8*5+:8] = 0; v[8*6+:8] = 255; v[8*7+:8] = 1; end
            15: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 204; v[8*4+:8] = 170; v[8*5+:8] = 136; v[8*6+:8] = 204; v[8*7+:8] = 0; end
            16: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 240; v[8*4+:8] = 15; v[8*5+:8] = 0; v[8*6+:8] = 15; v[8*7+:8] = 0; end
            17: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 255; v[8*4+:8] = 255; v[8*5+:8] = 255; v[8*6+:8] = 0; v[8*7+:8] = 255; end
            18: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 240; v[8*4+:8] = 15; v[8*5+:8] = 255; v[8*6+:8] = 240; v[8*7+:8] = 15; end
            19: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 204; v[8*4+:8] = 170; v[8*5+:8] = 238; v[8*6+:8] = 170; v[8*7+:8] = 0; end
            20: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 204; v[8*4+:8] = 170; v[8*5+:8] = 102; v[8*6+:8] = 0; v[8*7+:8] = 204; end
            21: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 170; v[8*4+:8] = 85; v[8*5+:8] = 255; v[8*6+:8] = 255; v[8*7+:8] = 85; end
            22: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 10; v[8*4+:8] = 42; v[8*5+:8] = 1; v[8*6+:8] = 0; v[8*7+:8] = 0; end
            23: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 127; v[8*4+:8] = 128; v[8*5+:8] = 1; v[8*6+:8] = 0; v[8*7+:8] = 1; end
            24: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 255; v[8*4+:8] = 0; v[8*5+:8] = 0; v[8*6+:8] = 1; v[8*7+:8] = 0; end
            25: begin v[8*1+:8] = 102; v[8*2+:8] = 1; v[8*3+:8] = 170; v[8*4+:8] = 204; v[8*5+:8] = 222; v[8*6+:8] = 136; v[8*7+:8] = 238; end
            26: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 204; v[8*4+:8] = 170; v[8*5+:8] = 102; v[8*6+:8] = 136; v[8*7+:8] = 34; end
            27: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 170; v[8*4+:8] = 204; v[8*5+:8] = 238; v[8*6+:8] = 1; v[8*7+:8] = 0; end
            28: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 170; v[8*4+:8] = 204; v[8*5+:8] = 102; v[8*6+:8] = 170; v[8*7+:8] = 0; end
            29: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 10; v[8*4+:8] = 42; v[8*5+:8] = 224; v[8*6+:8] = 10; v[8*7+:8] = 1; end
            30: begin v[8*1+:8] = 1; v[8*2+:8] = 2; v[8*3+:8] = 10; v[8*4+:8] = 42; v[8*5+:8] = 1; v[8*6+:8] = 255; v[8*7+:8] = 42; end
            endcase
            exp_regs = v;
        end
    endfunction

    // Set of registers (bit r = Rr) that must be written back at least once.
    function [7:0] exp_mask(input integer tid);
        begin
            case (tid)
            0:  exp_mask = (8'd1<<1) | (8'd1<<2);
            1:  exp_mask = (8'd1<<1) | (8'd1<<2);
            2:  exp_mask = (8'd1<<1) | (8'd1<<2) | (8'd1<<3) | (8'd1<<4);
            3:  exp_mask = (8'd1<<1) | (8'd1<<2) | (8'd1<<3) | (8'd1<<4) | (8'd1<<5);
            4:  exp_mask = (8'd1<<1) | (8'd1<<6) | (8'd1<<7);
            5:  exp_mask = (8'd1<<1) | (8'd1<<3) | (8'd1<<4) | (8'd1<<5);
            6:  exp_mask = (8'd1<<1) | (8'd1<<4);
            7:  exp_mask = (8'd1<<1) | (8'd1<<2) | (8'd1<<3) | (8'd1<<4);
            8:  exp_mask = (8'd1<<4) | (8'd1<<5);
            9:  exp_mask = (8'd1<<1) | (8'd1<<4) | (8'd1<<5);
            10: exp_mask = (8'd1<<3) | (8'd1<<4);
            11: exp_mask = (8'd1<<1) | (8'd1<<2) | (8'd1<<3) | (8'd1<<4);
            // tests 12-30: R1..R4 by the fixture loads, R5..R7 (or R1/R2) by the ALU ops: R1..R7 all written
            12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
            25, 26, 27, 28, 29, 30: exp_mask = 8'b1111_1110;
            default: exp_mask = 8'd0;
            endcase
        end
    endfunction

    // Number of cycles in which branch_taken must be asserted.
    function integer exp_bt(input integer tid);
        begin
            case (tid)
            6, 9:    exp_bt = 1;
            8:       exp_bt = 3;
            default: exp_bt = 0;
            endcase
        end
    endfunction

    function [8*48-1:0] test_name(input integer tid);
        begin
            case (tid)
            0:  test_name = "LOAD->LOAD (built-in instr_mem program)";
            1:  test_name = "LOAD->ADD";
            2:  test_name = "ADD->ADD chain (EX/MEM + MEM/WB forwarding)";
            3:  test_name = "ALU->LOAD address (distance 1 and 2)";
            4:  test_name = "Same-destination forwarding priority";
            5:  test_name = "R0 protection";
            6:  test_name = "Taken BEQ + wrong-path flush (LOAD->BEQ)";
            7:  test_name = "Not-taken BEQ";
            8:  test_name = "Backward BEQ (+ wrong-path BEQ flushed)";
            9:  test_name = "Wrong-path LOAD/ADD flushed (ALU->BEQ)";
            10: test_name = "Start-up: first instrs read non-R0 regs";
            11: test_name = "LOAD from never-written dmem address = 0";
            12: test_name = "SUB: normal / wrap / zero (42,10)";
            13: test_name = "SUB: boundaries (128,127), R0 operand";
            14: test_name = "SUB: equal 255,255 / R0 operands";
            15: test_name = "AND: normal / idempotent / R0 (204,170)";
            16: test_name = "AND: zero result (240,15)";
            17: test_name = "AND: all bits set (255,255)";
            18: test_name = "OR: all ones (240,15)";
            19: test_name = "OR: normal / R0 operand (204,170)";
            20: test_name = "XOR: normal / equal -> 0 (204,170)";
            21: test_name = "XOR: complementary (170,85)";
            22: test_name = "SLT: basic / reverse / equal (10,42)";
            23: test_name = "SLT: 127 vs 128 boundary (unsigned)";
            24: test_name = "SLT: 255 vs 0 boundary (unsigned)";
            25: test_name = "ALL OPS discriminate (170,204)";
            26: test_name = "Forwarded operands mix 1 (204,170)";
            27: test_name = "Forwarded operands mix 2 (170,204)";
            28: test_name = "Chain: XOR round trip (170,204)";
            29: test_name = "Chain: SUB wrap round trip (10,42)";
            30: test_name = "Chain: SLT -> SUB -> AND (10,42)";
            default: test_name = "?";
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // One CPU instance + monitors + final check per test
    // ------------------------------------------------------------------
    genvar g;
    generate
    for (g = 0; g < NUM_TESTS; g = g + 1) begin : t

        wire [3:0]  pc;
        wire [11:0] instr;
        wire        zero, branch_taken;

        cpu dut (
            .clk(clk),
            .pc(pc),
            .instr(instr),
            .zero(zero),
            .branch_taken(branch_taken)
        );

        integer    a, r;
        reg [7:0]  wr_mask;        // registers written back at least once
        integer    bt_count;       // cycles with branch_taken = 1
        reg        seen15, wrapped, x_reported, test_ok;
        reg [63:0] exp_v;

        // ---- load this test's program (test 0 keeps instr_mem.v's own program) ----
        initial begin
            if (g != 0) begin
                #1;
                for (a = 0; a < 16; a = a + 1)
                    dut.imem.memory[a] = prog(g, a);
                // ALU tests: preload the data-memory pointer chain DMEM[0]=1, [1]=2, [2]=A, [A]=B
                if (g >= FIRST_ALU_TEST) begin
                    dut.dp.dm.memory[0]        = 8'd1;
                    dut.dp.dm.memory[1]        = 8'd2;
                    dut.dp.dm.memory[2]        = op_a(g);
                    dut.dp.dm.memory[op_a(g)]  = op_b(g);
                end
            end
        end

        // ---- X / Z monitor (forwarding controls, branch, forwarded operands) ----
        task check_no_x;
            begin
                if (!x_reported &&
                    ( (^{dut.dp.fwd_id_wb_1, dut.dp.fwd_id_wb_2,
                         dut.dp.fwd_ex_mem_a, dut.dp.fwd_mem_wb_a,
                         dut.dp.fwd_ex_mem_b, dut.dp.fwd_mem_wb_b,
                         branch_taken, zero}) === 1'bx ||
                      (^{dut.dp.a_in, dut.dp.b_in, dut.dp.mem_stage_value,
                         dut.dp.mem_wb_wd}) === 1'bx )) begin
                    x_reported = 1'b1;
                    failures   = failures + 1;
                    $display("[FAIL] test %0d (%0s): X/Z on a forwarding or datapath signal at t=%0t",
                             g, test_name(g), $time);
                end
            end
        endtask

        initial begin
            wr_mask = 8'd0;  bt_count = 0;
            seen15 = 1'b0;   wrapped = 1'b0;  x_reported = 1'b0;
            #2 check_no_x;
        end

        // t = 0 is skipped: in some Icarus language modes the x->0 initialisation of clk
        // shows up as a negedge before the DUT initial blocks have run.
        always @(negedge clk) if ($time != 0) check_no_x;

        // ---- cycle monitor: sampled just BEFORE each edge (= values being committed) ----
        always @(posedge clk) begin
            if (dut.dp.mem_wb_we === 1'b1 && dut.dp.mem_wb_rd !== 3'd0)
                wr_mask[dut.dp.mem_wb_rd] = 1'b1;
            if (branch_taken === 1'b1)
                bt_count = bt_count + 1;
            if (pc === 4'd15)
                seen15 = 1'b1;
            else if (pc === 4'd0 && seen15)
                wrapped = 1'b1;          // PC wrapped: program started to re-execute
        end

        // ---- final check, just after edge CHECK_EDGE ----
        initial begin
            repeat (CHECK_EDGE) @(posedge clk);
            #1;
            test_ok = 1'b1;
            exp_v   = exp_regs(g);

            if (dut.dp.rf.regs[0] !== 8'd0) begin
                test_ok = 1'b0;
                $display("  [FAIL] test %0d: R0 = %0d (must always be 0)", g, dut.dp.rf.regs[0]);
            end
            for (r = 1; r < 8; r = r + 1)
                if (dut.dp.rf.regs[r] !== exp_v[8*r +: 8]) begin
                    test_ok = 1'b0;
                    $display("  [FAIL] test %0d: R%0d = %0d, expected %0d",
                             g, r, dut.dp.rf.regs[r], exp_v[8*r +: 8]);
                end
            if (wr_mask !== exp_mask(g)) begin
                test_ok = 1'b0;
                $display("  [FAIL] test %0d: registers written back = %b, expected %b (bit n = Rn)",
                         g, wr_mask, exp_mask(g));
            end
            if (bt_count !== exp_bt(g)) begin
                test_ok = 1'b0;
                $display("  [FAIL] test %0d: branch_taken asserted %0d times, expected %0d",
                         g, bt_count, exp_bt(g));
            end
            if (wrapped) begin
                test_ok = 1'b0;
                $display("  [FAIL] test %0d: PC wrapped before the check (program re-execution)", g);
            end
            if (x_reported) test_ok = 1'b0;

            if (test_ok)
                $display("[PASS] test %2d: %0s | R1..R7 = %0d %0d %0d %0d %0d %0d %0d | branch_taken x%0d",
                         g, test_name(g),
                         dut.dp.rf.regs[1], dut.dp.rf.regs[2], dut.dp.rf.regs[3],
                         dut.dp.rf.regs[4], dut.dp.rf.regs[5], dut.dp.rf.regs[6],
                         dut.dp.rf.regs[7], bt_count);
            else begin
                failures = failures + 1;
                $display("[FAIL] test %2d: %0s", g, test_name(g));
            end
        end

    end
    endgenerate

    // ------------------------------------------------------------------
    // Top-level: waveform dump and verdict
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0, cpu_tb);

        repeat (CHECK_EDGE) @(posedge clk);
        #5;                                   // all per-test checks ran at +1

        if (failures == 0) begin
            $display("ALL %0d TESTS PASSED (checked after clock edge %0d, before PC wrap)",
                     NUM_TESTS, CHECK_EDGE);
            $finish;
        end else
            $fatal(1, "%0d check(s) FAILED - see [FAIL] lines above", failures);
    end

endmodule
