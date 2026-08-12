// ============================================================================
// kavacha_core.sv — RV32IM, MULTI-CYCLE (non-pipelined) area-optimized core.
//
// Kavacha ("armour") is the AstraV family's tiny / area class: one instruction
// at a time through a small FSM — no pipeline, no forwarding, no hazard logic.
// It trades throughput for minimal area and trivially-provable correctness, and
// reuses the family's verified leaf cells (ALU, multiply/divide, register file,
// CSR file).
//
//   FETCH -> EXEC -> { (alu/branch/jump/store/csr/system) -> FETCH
//                      (load)   -> LOAD -> FETCH
//                      (muldiv) -> MD   -> FETCH }
//
// Verified against the golden RV32IM ISA model.
// ============================================================================
`include "kavacha_pkg.sv"

module kavacha_core
  import kavacha_pkg::*;
#(
  parameter logic [XLEN-1:0] RESET_PC = 32'h0000_0000,
  // SECURE=1 adds User mode + 8-region PMP for M/U memory isolation.
  // Default 0 keeps the minimal machine-mode-only footprint (byte-identical).
  parameter bit SECURE = 1'b0
)(
  input  logic              clk,
  input  logic              rst,
  output logic [XLEN-1:0]   imem_addr,
  input  logic [XLEN-1:0]   imem_rdata,
  output logic [XLEN-1:0]   dmem_addr,
  output logic              dmem_re,
  output logic              dmem_we,
  output logic [3:0]        dmem_be,
  output logic [XLEN-1:0]   dmem_wdata,
  input  logic [XLEN-1:0]   dmem_rdata,
  // interrupt pending lines (from CLINT/PLIC); tie 0 if unused
  input  logic              irq_timer,
  input  logic              irq_soft,
  input  logic              irq_ext,
  // memory wait-state: 1 = current fetch/load/store not ready (bus latency).
  // Tie 0 for zero-latency memory (behaviour unchanged).
  input  logic              mem_stall,
  output logic              mem_req,     // 1 = a fetch/load/store is in progress
  output logic              retire_valid,
  output logic [XLEN-1:0]   retire_pc,
  output logic [XLEN-1:0]   retire_instr,
  output logic              retire_rd_we,
  output logic [4:0]        retire_rd,
  output logic [XLEN-1:0]   retire_rd_val,
  // ---- RISC-V external debug (tie haltreq / ar_valid = 0 if no DM) ---------
  input  logic              dbg_haltreq,    // request entry to debug mode
  input  logic              dbg_resumereq,  // pulse: resume from debug
  output logic              dbg_halted,     // core is halted in debug mode
  input  logic              dbg_ar_valid,   // DM Access-Register request
  input  logic              dbg_ar_write,   // 1 = write, 0 = read
  input  logic              dbg_ar_csr,     // 1 = CSR access, 0 = GPR access
  input  logic [11:0]       dbg_ar_regno,   // GPR number (0-31) or CSR address
  input  logic [XLEN-1:0]   dbg_ar_wdata,
  output logic [XLEN-1:0]   dbg_ar_rdata,
  output logic              dbg_ar_done     // 1-cycle completion pulse
`ifdef RISCV_FORMAL
  ,
  // RISC-V Formal Interface (riscv-formal). Sampled when rvfi_valid=1. Lets the
  // standard riscv-formal checker prove ISA conformance.
  // Enabled only under -DRISCV_FORMAL (no synthesis cost).
  output logic              rvfi_valid,
  output logic [63:0]       rvfi_order,
  output logic [31:0]       rvfi_insn,
  output logic              rvfi_trap,
  output logic              rvfi_halt,
  output logic              rvfi_intr,
  output logic [1:0]        rvfi_mode,
  output logic [1:0]        rvfi_ixl,
  output logic [4:0]        rvfi_rs1_addr,
  output logic [4:0]        rvfi_rs2_addr,
  output logic [XLEN-1:0]   rvfi_rs1_rdata,
  output logic [XLEN-1:0]   rvfi_rs2_rdata,
  output logic [4:0]        rvfi_rd_addr,
  output logic [XLEN-1:0]   rvfi_rd_wdata,
  output logic [XLEN-1:0]   rvfi_pc_rdata,
  output logic [XLEN-1:0]   rvfi_pc_wdata,
  output logic [XLEN-1:0]   rvfi_mem_addr,
  output logic [3:0]        rvfi_mem_rmask,
  output logic [3:0]        rvfi_mem_wmask,
  output logic [XLEN-1:0]   rvfi_mem_rdata,
  output logic [XLEN-1:0]   rvfi_mem_wdata
`endif
);
  localparam logic [3:0] S_FETCH  = 4'd0;
  localparam logic [3:0] S_EXEC   = 4'd1;
  localparam logic [3:0] S_LOAD   = 4'd2;
  localparam logic [3:0] S_MD     = 4'd3;
  localparam logic [3:0] S_FETCH2 = 4'd4;
  localparam logic [3:0] S_LOAD2  = 4'd5;
  localparam logic [3:0] S_STORE2 = 4'd6;
  localparam logic [3:0] S_HALTED = 4'd7;
  logic [3:0] state;


  // ---- debug-mode state (RISC-V external debug) ----------------------------
  logic            dbg_mode;        // 1 = halted in debug mode
  logic [XLEN-1:0] dpc;             // debug PC (0x7b1)
  logic [XLEN-1:0] dscratch0;       // 0x7b2
  logic            dcsr_ebreakm;    // dcsr.ebreakm (0x7b0[15])
  logic            dcsr_step;       // dcsr.step    (0x7b0[2])
  logic [2:0]      dcsr_cause;      // dcsr.cause   (0x7b0[8:6]): 1=ebreak,3=haltreq,4=step
  logic            dbg_ar_busy;     // an Access-Register op is being serviced
  logic            step_pending;    // resumed with step=1
  logic            step_seen;       // the single stepped instruction committed
  assign dbg_halted = (state == S_HALTED);

  logic [XLEN-1:0] pc, instr;
  logic [2:0]      instr_len;   // bytes consumed by the current instruction (2 or 4)
  logic [15:0]     lo16;        // low half of a 32-bit instr that straddles a word

  // S_FETCH reads the word containing PC; S_FETCH2 reads the next word for a
  // 32-bit instruction that starts at a 2-byte (odd-halfword) boundary.
  assign imem_addr = (state == S_FETCH2) ? ({pc[XLEN-1:2], 2'b00} + 32'd4) : pc;

  // ---- RVC: decompress the 16-bit halfword at PC ---------------------------
  wire [15:0] fetch_half = pc[1] ? imem_rdata[31:16] : imem_rdata[15:0];
  wire [31:0] c_instr32;
  wire        c_is_comp, c_illegal;
  kavacha_rvc u_rvc (.instr16(fetch_half), .instr32(c_instr32),
                     .is_compressed(c_is_comp), .decomp_illegal(c_illegal));

  // ---- instruction field wires (const selects only in continuous assigns) --
  wire [2:0]  funct3 = instr[14:12];
  wire [4:0]  rs1    = instr[19:15];
  wire [4:0]  rs2    = instr[24:20];
  wire [4:0]  rd     = instr[11:7];
  wire [11:0] sys_imm12 = instr[31:20];

  // immediate generator (shared leaf cell)
  logic [XLEN-1:0] imm_i, imm_s, imm_b, imm_u, imm_j, id_imm;
  kavacha_immgen u_imm (.instr(instr),
    .imm_i(imm_i), .imm_s(imm_s), .imm_b(imm_b), .imm_u(imm_u), .imm_j(imm_j));

  // ---- register file -------------------------------------------------------
  logic [XLEN-1:0] rdata1, rdata2;
  logic            rf_we;
  logic [XLEN-1:0] wb_value;
  // debug GPR access steals the regfile ports while halted
  wire             dbg_do     = dbg_mode && dbg_ar_valid && !dbg_ar_busy;
  wire             dbg_gpr_we = dbg_do && dbg_ar_write && !dbg_ar_csr;
  wire [4:0]       rf_ra1 = (dbg_mode && dbg_ar_valid && !dbg_ar_csr) ? dbg_ar_regno[4:0] : rs1;
  wire [4:0]       rf_wa  = dbg_gpr_we ? dbg_ar_regno[4:0] : rd;
  wire [XLEN-1:0]  rf_wd  = dbg_gpr_we ? dbg_ar_wdata     : wb_value;
  wire             rf_we_eff = dbg_gpr_we | rf_we;
  // SECURE builds protect the GPRs with SECDED ECC (single-error-correct,
  // double-error-detect) for register-file hardening.
  wire ecc_cerr, ecc_uerr;
  generate if (SECURE) begin : g_rf_ecc
    kavacha_regfile_ecc #(.WRITE_FIRST(0)) u_rf (
      .clk(clk), .ra1(rf_ra1), .ra2(rs2), .rd1(rdata1), .rd2(rdata2),
      .we(rf_we_eff), .wa(rf_wa), .wd(rf_wd),
      .ecc_cerr(ecc_cerr), .ecc_uerr(ecc_uerr)
    );
  end else begin : g_rf
    kavacha_regfile #(.WRITE_FIRST(0)) u_rf (
      .clk(clk), .ra1(rf_ra1), .ra2(rs2), .rd1(rdata1), .rd2(rdata2),
      .we(rf_we_eff), .wa(rf_wa), .wd(rf_wd)
    );
    assign ecc_cerr = 1'b0;
    assign ecc_uerr = 1'b0;
  end endgenerate

  // ---- decode (shared base RV32IMC decoder leaf cell) ----------------------
  alu_op_e   d_alu_op;  br_op_e  d_br_op;  md_op_e d_md_op;  wb_sel_e d_wb_sel;
  logic d_use_pc, d_use_imm, d_reg_we, d_mem_re, d_mem_we, d_mem_unsigned;
  logic [1:0] d_mem_width;
  logic d_is_branch, d_is_jal, d_is_jalr, d_is_md, d_is_csr;
  logic d_is_ecall, d_is_ebreak, d_is_mret, d_illegal, d_uses_rs2;

  kavacha_decode u_dec (
    .instr(instr), .imm_i(imm_i), .imm_s(imm_s), .imm_b(imm_b),
    .imm_u(imm_u), .imm_j(imm_j),
    .alu_op(d_alu_op), .br_op(d_br_op), .md_op(d_md_op), .wb_sel(d_wb_sel),
    .use_pc(d_use_pc), .use_imm(d_use_imm), .reg_we(d_reg_we),
    .mem_re(d_mem_re), .mem_we(d_mem_we), .mem_unsigned(d_mem_unsigned),
    .mem_width(d_mem_width), .is_branch(d_is_branch), .is_jal(d_is_jal),
    .is_jalr(d_is_jalr), .is_md(d_is_md), .is_csr(d_is_csr),
    .is_ecall(d_is_ecall), .is_ebreak(d_is_ebreak), .is_mret(d_is_mret),
    .illegal(d_illegal), .uses_rs2(d_uses_rs2), .id_imm(id_imm)
  );

  // ---- datapath ------------------------------------------------------------
  wire [XLEN-1:0] alu_a = d_use_pc  ? pc     : rdata1;
  wire [XLEN-1:0] alu_b = d_use_imm ? id_imm : rdata2;
  logic [XLEN-1:0] alu_y;
  kavacha_alu u_alu (.op(d_alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

  logic br_taken;
  kavacha_branch u_br (.br_op(d_br_op), .a(rdata1), .b(rdata2), .taken(br_taken));

  // multiply/divide
  logic md_busy, md_done; logic [XLEN-1:0] md_result;
  kavacha_muldiv u_md (
    .clk(clk), .rst(rst), .start(state==S_EXEC && d_is_md),
    .op(d_md_op), .a(rdata1), .b(rdata2),
    .busy(md_busy), .done(md_done), .result(md_result)
  );

  // CSR
  wire  [1:0]      csr_fn = funct3[1:0];
  wire             csr_imm_mode = funct3[2];
  wire  [XLEN-1:0] csr_src = csr_imm_mode ? {27'b0, rs1} : rdata1;
  logic [XLEN-1:0] csr_rdata, csr_wval;
  always_comb unique case (csr_fn)
    2'b01:  csr_wval = csr_src;
    2'b10:  csr_wval = csr_rdata |  csr_src;
    2'b11:  csr_wval = csr_rdata & ~csr_src;
    default: csr_wval = csr_rdata;
  endcase
  wire csr_do_write = d_is_csr &&
       !((csr_fn != 2'b01) && (csr_imm_mode ? (rs1==5'd0) : (rs1==5'd0)));

  // EBREAK enters debug mode instead of trapping when dcsr.ebreakm is set.
  wire ebreak_to_debug = (state==S_EXEC) && d_is_ebreak && dcsr_ebreakm && !dbg_mode;

  // ---- privilege + PMP (security: M/U memory isolation) --------------------
  // Only elaborated when SECURE=1 (else zero-cost: priv stays M, no PMP logic).
  localparam int NPMP = 8;
  wire [1:0]   cur_priv;
  wire         fetch_m, data_m, mmwp_w;
  wire [127:0] pmpcfg_w;
  wire [511:0] pmpaddr_w;
  wire acc_fetch_fault, acc_load_fault, acc_store_fault;
  generate if (SECURE) begin : g_pmp
    wire pmp_fetch_fault, pmp_data_fault;
    kavacha_pmp #(.NPMP(NPMP)) u_pmp_if (    // instruction-fetch check
      .cfg(pmpcfg_w[8*NPMP-1:0]), .addrreg(pmpaddr_w[32*NPMP-1:0]),
      .addr(pc), .priv_m(fetch_m), .mmwp(mmwp_w), .do_r(1'b0), .do_w(1'b0), .do_x(1'b1),
      .fault(pmp_fetch_fault)
    );
    kavacha_pmp #(.NPMP(NPMP)) u_pmp_ls (    // load/store check
      .cfg(pmpcfg_w[8*NPMP-1:0]), .addrreg(pmpaddr_w[32*NPMP-1:0]),
      .addr(alu_y), .priv_m(data_m), .mmwp(mmwp_w), .do_r(d_mem_re), .do_w(d_mem_we), .do_x(1'b0),
      .fault(pmp_data_fault)
    );
    assign acc_fetch_fault = (state==S_EXEC) && pmp_fetch_fault;
    assign acc_load_fault  = (state==S_EXEC) && d_mem_re && pmp_data_fault;
    assign acc_store_fault = (state==S_EXEC) && d_mem_we && pmp_data_fault;
  end else begin : g_nopmp
    assign acc_fetch_fault = 1'b0;
    assign acc_load_fault  = 1'b0;
    assign acc_store_fault = 1'b0;
  end endgenerate
  wire acc_fault = acc_fetch_fault | acc_load_fault | acc_store_fault;

  // trap (priv-aware ecall cause; PMP access faults 1/5/7)
  wire ex_trap = (state==S_EXEC) &&
                 (d_illegal | d_is_ecall | (d_is_ebreak & ~dcsr_ebreakm) | acc_fault);
  wire [3:0] ex_cause = acc_fetch_fault ? 4'd1 :                         // instr access
                        d_illegal        ? CAUSE_ILLEGAL :
                        d_is_ecall       ? (cur_priv==2'b00 ? 4'd8 : CAUSE_ECALL_M) :
                        d_is_ebreak      ? CAUSE_BREAKPOINT :
                        acc_load_fault   ? 4'd5 :                         // load access
                        acc_store_fault  ? 4'd7 : CAUSE_ILLEGAL;          // store access
  wire [XLEN-1:0] ex_tval = acc_fetch_fault               ? pc :
                            (acc_load_fault|acc_store_fault) ? alu_y :
                            d_illegal                       ? instr : 32'b0;
  logic [XLEN-1:0] mtvec_w, mepc_w;
  logic [XLEN-1:0] seq_next;          // next PC ignoring interrupts (set below)
  wire             irq_req;
  wire [3:0]       irq_cause;

  wire [1:0] aoff = alu_y[1:0];
  // a misaligned access crosses a word boundary: word at off!=0, or half at off=3
  wire mis = (d_mem_width==2'd2 && aoff!=2'b00) || (d_mem_width==2'd1 && aoff==2'b11);

  // commit = the cycle an instruction finishes (misaligned mem takes a 2nd beat).
  // Memory commits are gated on !mem_stall so a not-ready bus never double-commits.
  wire commit = (state==S_EXEC && !d_mem_re && !d_is_md && !(d_mem_we && mis)
                                && !(d_mem_we && mem_stall) && !ebreak_to_debug) ||
                (state==S_LOAD && !mis && !mem_stall) ||
                (state==S_LOAD2 && !mem_stall) ||
                (state==S_STORE2 && !mem_stall) ||
                (state==S_MD && md_done);

  // Take an interrupt at an instruction boundary: only when this instruction
  // commits with no synchronous trap, and isn't an MRET/CSR op (so we never
  // collide with the CSR file's mret/csr-write paths). mepc = where we'd resume.
  wire take_irq = commit && irq_req && !ex_trap && !d_is_mret && !d_is_csr;

  // debug CSR access (Access Register, abstract): dpc/dcsr/dscratch0 are local;
  // every other CSR is serviced by the shared CSR file with csr_addr stolen.
  wire        dbg_csr_local = (dbg_ar_regno==12'h7b0)||(dbg_ar_regno==12'h7b1)||(dbg_ar_regno==12'h7b2);
  wire        dbg_csr_we    = dbg_do && dbg_ar_write && dbg_ar_csr && !dbg_csr_local;
  wire [11:0] csr_addr_eff  = dbg_mode ? dbg_ar_regno : sys_imm12;
  wire        csr_we_eff    = dbg_mode ? dbg_csr_we   : (commit && csr_do_write && !ex_trap);
  wire [XLEN-1:0] csr_wdata_eff = dbg_mode ? dbg_ar_wdata : csr_wval;

  kavacha_csr #(.MISA_VAL((32'b01<<30)|(1<<8)|(1<<12)|(1<<2)),  // RV32IMC
                .U_MODE(SECURE), .PMP_REGIONS(SECURE ? NPMP : 0)) u_csr (  // secure opt
    .clk(clk), .rst(rst),
    .csr_addr(csr_addr_eff), .csr_rdata(csr_rdata),
    .csr_we(csr_we_eff), .csr_wdata(csr_wdata_eff),
    .priv_o(cur_priv), .fetch_m_o(fetch_m), .data_m_o(data_m), .mmwp_o(mmwp_w),
    .pmpcfg_o(pmpcfg_w), .pmpaddr_o(pmpaddr_w),
    .trap_set((commit && ex_trap) || take_irq),
    .trap_cause(ex_trap ? ex_cause : irq_cause),
    .trap_interrupt(take_irq),
    .trap_epc(ex_trap ? pc : seq_next),
    .trap_tval(ex_tval),                      // mtval = faulting instr / address
    .irq_timer(irq_timer), .irq_soft(irq_soft), .irq_ext(irq_ext),
    .mret(commit && d_is_mret), .retire(commit),
    .mtvec_o(mtvec_w), .mepc_o(mepc_w),
    .irq_req(irq_req), .irq_cause(irq_cause)
  );

  // ---- debug Access-Register read data + dcsr ------------------------------
  // dcsr: xdebugver=4, ebreakm, cause[8:6], step, prv=M(3)
  wire [XLEN-1:0] dcsr_val = {4'd4, 12'd0, dcsr_ebreakm, 6'd0,
                              dcsr_cause, 3'd0, dcsr_step, 2'b11};
  assign dbg_ar_rdata = !dbg_ar_csr              ? rdata1     :  // GPR (ra1 = regno)
                        (dbg_ar_regno==12'h7b0)  ? dcsr_val   :
                        (dbg_ar_regno==12'h7b1)  ? dpc        :
                        (dbg_ar_regno==12'h7b2)  ? dscratch0  :
                        csr_rdata;                                // CSR (addr = regno)

  // ---- memory ports (unified shift path; misaligned = two beats) -----------
  wire is_load_ex  = (state==S_EXEC) && d_mem_re && !ex_trap;
  wire is_store_ex = (state==S_EXEC) && d_mem_we && !ex_trap;
  logic [31:0] ld_w0;                       // first word captured for a misaligned load

  assign dmem_addr = (state==S_LOAD2 || state==S_STORE2)
                       ? ({alu_y[XLEN-1:2],2'b00} + 32'd4) : {alu_y[XLEN-1:2],2'b00};
  assign dmem_re   = (state==S_LOAD) || (state==S_LOAD2);
  assign dmem_we   = is_store_ex || (state==S_STORE2);
  // a memory transaction is in progress (for an external bus to act on)
  assign mem_req   = (state==S_FETCH) || (state==S_FETCH2) ||
                     (state==S_LOAD)  || (state==S_LOAD2)  ||
                     (state==S_STORE2) || is_store_ex;

  // store value placed at the byte offset within an 8-byte window
  wire [31:0] st_val = (d_mem_width==2'd0) ? {24'b0, rdata2[7:0]} :
                       (d_mem_width==2'd1) ? {16'b0, rdata2[15:0]} : rdata2;
  wire [63:0] st_sh  = {32'b0, st_val} << {aoff, 3'b000};      // << aoff*8
  wire [7:0]  be8    = (((d_mem_width==2'd0)?8'h01:(d_mem_width==2'd1)?8'h03:8'h0F)) << aoff;
  assign dmem_be     = (state==S_STORE2) ? be8[7:4] : (is_store_ex ? be8[3:0] : 4'b0000);
  assign dmem_wdata  = (state==S_STORE2) ? st_sh[63:32] : st_sh[31:0];

  // load assembly: {word1,word0} >> aoff*8, then width-extract
  wire [63:0] ld_comb = (state==S_LOAD2) ? {dmem_rdata, ld_w0} : {32'b0, dmem_rdata};
  wire [63:0] ld_sh   = ld_comb >> {aoff, 3'b000};
  wire [7:0]  lb = ld_sh[7:0]; wire [15:0] lh = ld_sh[15:0]; wire [31:0] lw = ld_sh[31:0];
  wire [XLEN-1:0] load_data =
      (d_mem_width==2'd0) ? (d_mem_unsigned ? {24'b0,lb} : {{24{lb[7]}},lb}) :
      (d_mem_width==2'd1) ? (d_mem_unsigned ? {16'b0,lh} : {{16{lh[15]}},lh}) : lw;

  // ---- writeback value -----------------------------------------------------
  always_comb begin
    if (state==S_LOAD || state==S_LOAD2) wb_value = load_data;
    else if (state==S_MD)   wb_value = md_result;
    else unique case (d_wb_sel)
      WB_PC4 : wb_value = pc + {29'd0, instr_len};   // link = PC + (2 or 4)
      WB_CSR : wb_value = csr_rdata;
      WB_MD  : wb_value = md_result;
      default: wb_value = alu_y;
    endcase
  end

  assign rf_we = commit && d_reg_we && !ex_trap && (rd != 5'd0);

  // ---- next PC -------------------------------------------------------------
  wire [XLEN-1:0] jalr_t = (rdata1 + id_imm) & ~32'd1;
  always_comb begin
    seq_next = pc + {29'd0, instr_len};
    if (commit) begin
      if      (ex_trap)                       seq_next = mtvec_w;
      else if (d_is_mret)                     seq_next = mepc_w;
      else if (d_is_jal)                      seq_next = pc + id_imm;
      else if (d_is_jalr)                     seq_next = jalr_t;
      else if (d_is_branch && br_taken)       seq_next = pc + id_imm;
    end
  end
  // an accepted interrupt diverts to the trap vector; mepc was saved as seq_next
  wire [XLEN-1:0] next_pc = take_irq ? mtvec_w : seq_next;

  // ---- FSM -----------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= S_FETCH;
      pc    <= RESET_PC;
      instr <= 32'h0000_0013;
      instr_len <= 3'd4;
      lo16  <= 16'h0;
      dbg_mode <= 1'b0; dpc <= '0; dscratch0 <= '0;
      dcsr_ebreakm <= 1'b0; dcsr_step <= 1'b0; dcsr_cause <= 3'd0;
      dbg_ar_busy <= 1'b0; dbg_ar_done <= 1'b0;
      step_pending <= 1'b0; step_seen <= 1'b0;
    end else begin
      // ---- debug Access-Register servicing (while halted) ------------------
      dbg_ar_done <= 1'b0;
      if (dbg_do) begin
        dbg_ar_busy <= 1'b1;
        dbg_ar_done <= 1'b1;
        if (dbg_ar_write && dbg_ar_csr) unique case (dbg_ar_regno)
          12'h7b0: begin dcsr_ebreakm <= dbg_ar_wdata[15]; dcsr_step <= dbg_ar_wdata[2]; end
          12'h7b1: dpc       <= dbg_ar_wdata;
          12'h7b2: dscratch0 <= dbg_ar_wdata;
          default: ;
        endcase
      end
      if (!dbg_ar_valid) dbg_ar_busy <= 1'b0;
      // record that the single stepped instruction has retired
      if (commit && !dbg_mode && step_pending) step_seen <= 1'b1;

      unique case (state)
        S_FETCH: if (!mem_stall) begin       // wait for the fetch to be ready
          if (dbg_haltreq && !dbg_mode) begin           // external halt request
            dpc <= pc; dcsr_cause <= 3'd3; dbg_mode <= 1'b1; state <= S_HALTED;
          end else if (step_pending && step_seen) begin // single-step complete
            dpc <= pc; dcsr_cause <= 3'd4; dbg_mode <= 1'b1; state <= S_HALTED;
            step_pending <= 1'b0; step_seen <= 1'b0;
          end else if (c_is_comp) begin
            instr     <= c_illegal ? 32'h0000_0000 : c_instr32;  // 0 => illegal
            instr_len <= 3'd2;
            state     <= S_EXEC;
          end else if (!pc[1]) begin
            instr     <= imem_rdata;       // aligned 32-bit
            instr_len <= 3'd4;
            state     <= S_EXEC;
          end else begin
            lo16  <= imem_rdata[31:16];    // straddle: grab next word
            state <= S_FETCH2;
          end
        end
        S_FETCH2: if (!mem_stall) begin
          instr     <= {imem_rdata[15:0], lo16};
          instr_len <= 3'd4;
          state     <= S_EXEC;
        end
        S_EXEC: begin
          if      (ebreak_to_debug) begin       // EBREAK with dcsr.ebreakm
            dpc <= pc; dcsr_cause <= 3'd1; dbg_mode <= 1'b1; state <= S_HALTED;
          end
          else if (d_mem_re && !ex_trap)        state <= S_LOAD;
          else if (d_is_md  && !ex_trap)        state <= S_MD;
          else if (d_mem_we && !ex_trap && mis) begin
            if (!mem_stall) state <= S_STORE2;   // hold beat0 until accepted
          end
          else if (d_mem_we && !ex_trap) begin
            if (!mem_stall) begin pc <= next_pc; state <= S_FETCH; end  // aligned store
          end
          else begin pc <= next_pc; state <= S_FETCH; end                // ALU/branch
        end
        S_LOAD: if (!mem_stall) begin
          if (mis) begin ld_w0 <= dmem_rdata; state <= S_LOAD2; end
          else     begin pc <= next_pc; state <= S_FETCH; end
        end
        S_LOAD2:  if (!mem_stall) begin pc <= next_pc; state <= S_FETCH; end
        S_STORE2: if (!mem_stall) begin pc <= next_pc; state <= S_FETCH; end
        S_MD:   if (md_done) begin pc <= next_pc; state <= S_FETCH; end
        S_HALTED: if (dbg_resumereq) begin    // resume from debug mode
          dbg_mode <= 1'b0; pc <= dpc; state <= S_FETCH;
          step_pending <= dcsr_step; step_seen <= 1'b0;
        end
        default: state <= S_FETCH;
      endcase
    end
  end

  // ---- retire trace --------------------------------------------------------
  assign retire_valid  = commit;
  assign retire_pc     = pc;
  assign retire_instr  = instr;
  assign retire_rd_we  = rf_we;
  assign retire_rd     = rd;
  assign retire_rd_val = wb_value;

  // ---- RISC-V Formal Interface --------------------------------------------
`ifdef RISCV_FORMAL
  logic [63:0] rvfi_order_r;
  logic        rvfi_intr_r;     // next retire is the first instr of a handler
  always_ff @(posedge clk) begin
    if (rst) begin
      rvfi_order_r <= 64'd0;
      rvfi_intr_r  <= 1'b0;
    end else if (commit) begin
      rvfi_order_r <= rvfi_order_r + 64'd1;
      rvfi_intr_r  <= ex_trap | take_irq;   // we just vectored to mtvec
    end
  end

  assign rvfi_valid     = commit;
  assign rvfi_order     = rvfi_order_r;
  assign rvfi_insn      = instr;
  assign rvfi_trap      = ex_trap;
  assign rvfi_halt      = 1'b0;
  assign rvfi_intr      = rvfi_intr_r;
  assign rvfi_mode      = 2'b11;            // M-mode only
  assign rvfi_ixl       = 2'b01;            // XLEN = 32
  assign rvfi_rs1_addr  = rs1;
  assign rvfi_rs2_addr  = d_uses_rs2 ? rs2 : 5'd0;
  assign rvfi_rs1_rdata = rdata1;
  assign rvfi_rs2_rdata = d_uses_rs2 ? rdata2 : 32'd0;
  assign rvfi_rd_addr   = rf_we ? rd : 5'd0;
  assign rvfi_rd_wdata  = rf_we ? wb_value : 32'd0;   // x0 => wdata must be 0
  assign rvfi_pc_rdata  = pc;
  assign rvfi_pc_wdata  = next_pc;
  // memory channel (effective word-aligned access; byte masks from width/offset)
  assign rvfi_mem_addr  = {alu_y[XLEN-1:2], 2'b00};
  assign rvfi_mem_rmask = d_mem_re ? be8[3:0] : 4'd0;
  assign rvfi_mem_wmask = d_mem_we ? dmem_be  : 4'd0;
  assign rvfi_mem_rdata = dmem_rdata;
  assign rvfi_mem_wdata = dmem_wdata;
`endif
endmodule
