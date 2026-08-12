// ============================================================================
// kavacha_pkg.sv — Shared types & constants for the Kavacha RV32IMC core.
//
// Common datapath definitions used by the core and its leaf cells: XLEN,
// opcode/funct encodings, the decoded control bundle, and the ALU / branch
// operation selectors.
// ============================================================================
`ifndef KAVACHA_PKG_SV
`define KAVACHA_PKG_SV

package kavacha_pkg;

  // ---- Word geometry -------------------------------------------------------
  localparam bit [31:0] XLEN = 32;



  // ---- Major opcodes (instr[6:0]) -----------------------------------------
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_OPIMM  = 7'b0010011;
  localparam logic [6:0] OP_OP     = 7'b0110011;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;

  // ---- ALU operations ------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND,
    ALU_PASS_B   // pass operand B straight through (LUI)
  } alu_op_e;

  // ---- M-extension operations ---------------------------------------------
  typedef enum logic [2:0] {
    MD_MUL, MD_MULH, MD_MULHSU, MD_MULHU,
    MD_DIV, MD_DIVU, MD_REM, MD_REMU
  } md_op_e;

  // ---- Branch/compare functions -------------------------------------------
  typedef enum logic [2:0] {
    BR_EQ, BR_NE, BR_LT, BR_GE, BR_LTU, BR_GEU, BR_NONE
  } br_op_e;

  // ---- Writeback source ----------------------------------------------------
  typedef enum logic [2:0] {
    WB_ALU, WB_MEM, WB_PC4, WB_CSR, WB_MD
  } wb_sel_e;

  // ---- Trap causes (mcause, interrupt bit = 0) ----------------------------
  localparam logic [3:0] CAUSE_ILLEGAL    = 4'd2;
  localparam logic [3:0] CAUSE_BREAKPOINT = 4'd3;
  localparam logic [3:0] CAUSE_ECALL_M    = 4'd11;

  // ---- CSR addresses we implement -----------------------------------------
  localparam logic [11:0] CSR_MSTATUS  = 12'h300;
  localparam logic [11:0] CSR_MIE      = 12'h304;
  localparam logic [11:0] CSR_MTVEC    = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH = 12'h340;
  localparam logic [11:0] CSR_MEPC     = 12'h341;
  localparam logic [11:0] CSR_MCAUSE   = 12'h342;
  localparam logic [11:0] CSR_MTVAL    = 12'h343;
  localparam logic [11:0] CSR_MIP      = 12'h344;
  localparam logic [11:0] CSR_MCYCLE   = 12'hB00;
  localparam logic [11:0] CSR_MINSTRET = 12'hB02;
  localparam logic [11:0] CSR_MCYCLEH  = 12'hB80;
  localparam logic [11:0] CSR_MISA     = 12'h301;
  localparam logic [11:0] CSR_MVENDORID= 12'hF11;
  localparam logic [11:0] CSR_MARCHID  = 12'hF12;
  localparam logic [11:0] CSR_MHARTID  = 12'hF14;

endpackage : kavacha_pkg

`endif
