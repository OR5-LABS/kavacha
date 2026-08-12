// ============================================================================
// kavacha_decode.sv — base RV32IM(C) instruction decoder (shared leaf cell).
//
// One combinational decode of the (already RVC-expanded) 32-bit instruction
// into the control bundle + the selected immediate. This is the single source
// of truth for instruction decoding, shared by the core and its leaf cells.
// ============================================================================
`include "kavacha_pkg.sv"

module kavacha_decode
  import kavacha_pkg::*;
(
  input  logic [31:0]     instr,
  input  logic [XLEN-1:0] imm_i,
  input  logic [XLEN-1:0] imm_s,
  input  logic [XLEN-1:0] imm_b,
  input  logic [XLEN-1:0] imm_u,
  input  logic [XLEN-1:0] imm_j,

  output alu_op_e         alu_op,
  output br_op_e          br_op,
  output md_op_e          md_op,
  output wb_sel_e         wb_sel,
  output logic            use_pc,
  output logic            use_imm,
  output logic            reg_we,
  output logic            mem_re,
  output logic            mem_we,
  output logic            mem_unsigned,
  output logic [1:0]      mem_width,
  output logic            is_branch,
  output logic            is_jal,
  output logic            is_jalr,
  output logic            is_md,
  output logic            is_csr,
  output logic            is_ecall,
  output logic            is_ebreak,
  output logic            is_mret,
  output logic            illegal,
  output logic            uses_rs2,
  output logic [XLEN-1:0] id_imm
);
  wire [6:0]  opcode = instr[6:0];
  wire [2:0]  funct3 = instr[14:12];
  wire [6:0]  funct7 = instr[31:25];
  wire [4:0]  shamt_i   = instr[24:20];
  wire [11:0] sys_imm12 = instr[31:20];

  always_comb begin
    alu_op=ALU_ADD; br_op=BR_NONE; md_op=MD_MUL; wb_sel=WB_ALU;
    use_pc=0; use_imm=1; reg_we=0; mem_re=0; mem_we=0;
    mem_width=2'd2; mem_unsigned=0; is_branch=0; is_jal=0; is_jalr=0;
    is_md=0; is_csr=0; is_ecall=0; is_ebreak=0; is_mret=0;
    illegal=0; uses_rs2=0; id_imm=imm_i;
    unique case (opcode)
      OP_LUI:   begin alu_op=ALU_PASS_B; id_imm=imm_u; reg_we=1; end
      OP_AUIPC: begin alu_op=ALU_ADD; use_pc=1; id_imm=imm_u; reg_we=1; end
      OP_JAL:   begin is_jal=1; wb_sel=WB_PC4; reg_we=1; id_imm=imm_j; end
      OP_JALR:  begin is_jalr=1; wb_sel=WB_PC4; reg_we=1; id_imm=imm_i;
                      if (funct3!=3'b000) illegal=1; end
      OP_BRANCH: begin
        is_branch=1; id_imm=imm_b; uses_rs2=1;
        unique case (funct3)
          3'b000:br_op=BR_EQ; 3'b001:br_op=BR_NE; 3'b100:br_op=BR_LT;
          3'b101:br_op=BR_GE; 3'b110:br_op=BR_LTU; 3'b111:br_op=BR_GEU;
          default:illegal=1;
        endcase
      end
      OP_LOAD: begin
        mem_re=1; reg_we=1; wb_sel=WB_MEM; id_imm=imm_i; alu_op=ALU_ADD;
        unique case (funct3)
          3'b000:begin mem_width=2'd0; mem_unsigned=0; end
          3'b001:begin mem_width=2'd1; mem_unsigned=0; end
          3'b010:begin mem_width=2'd2; mem_unsigned=0; end
          3'b100:begin mem_width=2'd0; mem_unsigned=1; end
          3'b101:begin mem_width=2'd1; mem_unsigned=1; end
          default:illegal=1;
        endcase
      end
      OP_STORE: begin
        mem_we=1; id_imm=imm_s; alu_op=ALU_ADD; uses_rs2=1;
        unique case (funct3)
          3'b000:mem_width=2'd0; 3'b001:mem_width=2'd1; 3'b010:mem_width=2'd2;
          default:illegal=1;
        endcase
      end
      OP_OPIMM: begin
        reg_we=1; id_imm=imm_i;
        unique case (funct3)
          3'b000:alu_op=ALU_ADD; 3'b010:alu_op=ALU_SLT; 3'b011:alu_op=ALU_SLTU;
          3'b100:alu_op=ALU_XOR; 3'b110:alu_op=ALU_OR;  3'b111:alu_op=ALU_AND;
          3'b001:begin alu_op=ALU_SLL; if(funct7!=0)illegal=1; id_imm={27'b0,shamt_i}; end
          3'b101:begin id_imm={27'b0,shamt_i};
                       if(funct7==7'b0000000)alu_op=ALU_SRL;
                       else if(funct7==7'b0100000)alu_op=ALU_SRA;
                       else illegal=1; end
          default:illegal=1;
        endcase
      end
      OP_OP: begin
        reg_we=1; use_imm=0; uses_rs2=1;
        if (funct7==7'b0000001) begin
          is_md=1; wb_sel=WB_MD;
          unique case (funct3)
            3'b000:md_op=MD_MUL; 3'b001:md_op=MD_MULH; 3'b010:md_op=MD_MULHSU;
            3'b011:md_op=MD_MULHU; 3'b100:md_op=MD_DIV; 3'b101:md_op=MD_DIVU;
            3'b110:md_op=MD_REM; 3'b111:md_op=MD_REMU; default:illegal=1;
          endcase
        end else begin
          unique case (funct3)
            3'b000:alu_op=(funct7==7'b0100000)?ALU_SUB:ALU_ADD;
            3'b001:alu_op=ALU_SLL; 3'b010:alu_op=ALU_SLT; 3'b011:alu_op=ALU_SLTU;
            3'b100:alu_op=ALU_XOR;
            3'b101:alu_op=(funct7==7'b0100000)?ALU_SRA:ALU_SRL;

            3'b110:alu_op=ALU_OR; 3'b111:alu_op=ALU_AND; default:illegal=1;
          endcase
          if (funct7!=7'b0000000 && funct7!=7'b0100000) illegal=1;
        end
      end
      OP_SYSTEM: begin
        if (funct3==3'b000) begin
          unique case (sys_imm12)
            12'h000:is_ecall=1; 12'h001:is_ebreak=1; 12'h302:is_mret=1;
            default:illegal=1;
          endcase
        end else begin is_csr=1; reg_we=1; wb_sel=WB_CSR; end
      end
      OP_FENCE: ; // nop
      default: illegal=1;
    endcase
  end
endmodule
