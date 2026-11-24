# Custom 8-bit RISC CPU — ISA v1

## Registers

8 general-purpose 8-bit registers:

R0–R7

R0 is hardwired to zero.
Writes to R0 are ignored.

## Instruction width

12 bits

## R-type format

[11:9] opcode
[8:6]  rs1
[5:3]  rs2
[2:0]  rd

## Instruction set

000 ADD
    Rd = Rs1 + Rs2

001 SUB
    Rd = Rs1 - Rs2

010 AND
    Rd = Rs1 & Rs2

011 OR
    Rd = Rs1 | Rs2

100 SLT
    Rd = (Rs1 < Rs2) ? 1 : 0

101 XOR
    Rd = Rs1 ^ Rs2

110 BEQ
    if (Rs1 == Rs2)
        PC = (address of this BEQ + sign_extended(offset)) mod 16

111 LOAD
    LOAD rd, [rs1]
    Rd = DMEM[Rs1]

## LOAD

LOAD reads one byte from data memory.

    LOAD rd, [rs1]
    R[rd] = DMEM[R[rs1]]

- The contents of register `rs1` are used as the 8-bit data-memory address.
- The byte read from that address is written into `rd`.
- The `rs2` field (instr[5:3]) is not used by LOAD. It is written as 000 by convention.
- Writes to R0 are ignored, as for every instruction.
- LOAD to R0 therefore has no architectural effect.
- A LOAD may use the result of the immediately preceding instruction as its
  address (including a preceding LOAD). No software-visible stall or delay slot
  is required.

The earlier external-data form of LOAD (`Rd = external_data`) is retired. The
CPU has no external data input.

## Data memory

- 256 locations x 8 bits, byte addressed by an 8-bit address.
- Read is asynchronous (combinational).
- There is no STORE instruction. Data memory is read-only from the program's point of view.
- All locations are initialised to 0, except two preset test locations:
    - DMEM[0]  = 10
    - DMEM[10] = 42

## Branch

BEQ uses instr[2:0] as a signed 3-bit offset (two's complement, range -4 to +3).
BEQ does not write any register; the offset occupies the field that other
instructions use as rd.

Target, when Rs1 == Rs2:
    PC_target = (address of the BEQ instruction + sign_extended(offset)) mod 16

- The offset is relative to the address of the BEQ instruction itself.
  It is NOT relative to the address of the following instruction (not PC+1).
- The program counter is 4 bits wide, so the target wraps modulo 16.
- If Rs1 != Rs2 the branch is not taken and execution continues with the
  next instruction.
- There is no branch delay slot. After a taken BEQ, the next instruction
  executed is the one at the target address.

Offset encoding (instr[2:0]):
    000 =  0    001 = +1    010 = +2    011 = +3
    100 = -4    101 = -3    110 = -2    111 = -1

Examples (BEQ address, offset -> target):
    address  1, offset +3 -> 4
    address  3, offset -2 -> 1
    address  1, offset -4 -> 13    (wraps modulo 16)
    address 15, offset +1 -> 0     (wraps modulo 16)
    address  2, offset  0 -> 2     (branches to itself)

## NOP

000_000_000_000

This is technically:
    ADD R0,R0 -> R0

It behaves as a NOP because R0 is hardwired to zero.

## Unconditional branch

BEQ R0,R0,offset

Since R0 is always zero, the condition is always true.

BEQ R0,R0,0 branches to itself, so execution never proceeds past it.
