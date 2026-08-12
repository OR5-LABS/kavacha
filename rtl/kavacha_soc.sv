// ============================================================================
// kavacha_soc.sv — Minimal SoC wrapper for the multi-cycle Kavacha core.
// Address map matches the family: IMEM @0, tohost @0x2000_0000, DRAM @0x8000_0000.
//
// Includes the RISC-V Debug Module + JTAG DTM (kavacha_debug). Drive the JTAG
// pins from an external adapter (OpenOCD); tie tck/tms/tdi low if unused.
// ============================================================================
`include "kavacha_pkg.sv"

module kavacha_soc
  import kavacha_pkg::*;
#(
  parameter bit [31:0] IMEM_WORDS = 8192,
  parameter bit [31:0] DRAM_WORDS = 8192,


  parameter logic [XLEN-1:0] DRAM_BASE   = 32'h8000_0000,
  parameter logic [XLEN-1:0] TOHOST_ADDR = 32'h2000_0000,
`ifdef KAVACHA_SECURE
  parameter bit SECURE = 1'b1     // -DKAVACHA_SECURE -> User mode + PMP
`else
  parameter bit SECURE = 1'b0     // default: minimal machine-mode-only footprint
`endif
)(
  input  logic              clk,
  input  logic              rst,
  // JTAG debug pins (tie 0 if unused)
  input  logic              tck,
  input  logic              tms,
  input  logic              tdi,
  output logic              tdo,
  output logic [XLEN-1:0]   tohost,
  output logic              tohost_we,
  output logic              retire_valid,
  output logic [XLEN-1:0]   retire_pc,
  output logic [XLEN-1:0]   retire_instr,
  output logic              retire_rd_we,
  output logic [4:0]        retire_rd,
  output logic [XLEN-1:0]   retire_rd_val
);
  logic [XLEN-1:0] imem [0:IMEM_WORDS-1];
  logic [XLEN-1:0] dram [0:DRAM_WORDS-1];

  logic [XLEN-1:0] imem_addr, imem_rdata;
  logic [XLEN-1:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic            dmem_re, dmem_we;
  logic [3:0]      dmem_be;

  // ---- CLINT (timer + software interrupt) ----------------------------------
  logic [63:0] mtime, mtimecmp;
  logic        msip;
  wire         irq_timer_w = (mtime >= mtimecmp);
  wire         irq_soft_w  = msip;

  // ---- debug module <-> core interface -------------------------------------
  wire        dbg_haltreq, dbg_resumereq, dbg_halted, ndmreset;
  wire        dbg_ar_valid, dbg_ar_write, dbg_ar_csr, dbg_ar_done;
  wire [11:0] dbg_ar_regno;
  wire [31:0] dbg_ar_wdata, dbg_ar_rdata;
  // system-bus master (DM -> memory)
  wire        dm_mem_valid, dm_mem_write;
  wire [31:0] dm_mem_addr, dm_mem_wdata;
  logic [31:0] dm_mem_rdata;
  logic        dm_mem_ready;

  wire core_rst = rst | ndmreset;     // ndmreset resets the hart, not the DM

  kavacha_core #(.SECURE(SECURE)) u_core (
    .clk(clk), .rst(core_rst),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
    .dmem_be(dmem_be), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
    .irq_timer(irq_timer_w), .irq_soft(irq_soft_w), .irq_ext(1'b0),
    .mem_stall(1'b0),
    .retire_valid(retire_valid), .retire_pc(retire_pc),
    .retire_instr(retire_instr), .retire_rd_we(retire_rd_we),
    .retire_rd(retire_rd), .retire_rd_val(retire_rd_val),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done)
  );

  kavacha_debug u_dbg (
    .clk(clk), .rst(rst),
    .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq),
    .ndmreset(ndmreset), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done),
    .dm_mem_valid(dm_mem_valid), .dm_mem_write(dm_mem_write),
    .dm_mem_addr(dm_mem_addr), .dm_mem_wdata(dm_mem_wdata),
    .dm_mem_rdata(dm_mem_rdata), .dm_mem_ready(dm_mem_ready)
  );

  wire [$clog2(IMEM_WORDS)-1:0] imem_idx = imem_addr[$clog2(IMEM_WORDS)+1:2];
  assign imem_rdata = imem[imem_idx];

  wire in_dram = (dmem_addr >= DRAM_BASE) && (dmem_addr < DRAM_BASE + DRAM_WORDS*4);
  wire [$clog2(DRAM_WORDS)-1:0] dram_idx =
        dmem_addr[$clog2(DRAM_WORDS)+1:2] - DRAM_BASE[$clog2(DRAM_WORDS)+1:2];
  wire in_imem = (dmem_addr < IMEM_WORDS*4);
  wire [$clog2(IMEM_WORDS)-1:0] imem_didx = dmem_addr[$clog2(IMEM_WORDS)+1:2];
  wire in_clint = (dmem_addr[31:16] == 16'h0200);
  wire [31:0] mtime_lo = mtime[31:0], mtime_hi = mtime[63:32];
  wire [31:0] mtimecmp_lo = mtimecmp[31:0], mtimecmp_hi = mtimecmp[63:32];
  wire [31:0] clint_rdata =
        (dmem_addr[15:0]==16'h0000) ? {31'b0, msip}    :
        (dmem_addr[15:0]==16'h4000) ? mtimecmp_lo      :
        (dmem_addr[15:0]==16'h4004) ? mtimecmp_hi      :
        (dmem_addr[15:0]==16'hBFF8) ? mtime_lo         :
        (dmem_addr[15:0]==16'hBFFC) ? mtime_hi         : 32'h0;
  assign dmem_rdata = in_dram  ? dram[dram_idx] :
                      in_clint ? clint_rdata :
                      in_imem  ? imem[imem_didx] : 32'h0;

  logic            tohost_we_r;
  logic [XLEN-1:0] tohost_r;
  assign tohost    = tohost_r;
  assign tohost_we = tohost_we_r;

  wire [XLEN-1:0] cur_word = dram[dram_idx];
  wire [XLEN-1:0] merged_word = {
    dmem_be[3] ? dmem_wdata[31:24] : cur_word[31:24],
    dmem_be[2] ? dmem_wdata[23:16] : cur_word[23:16],
    dmem_be[1] ? dmem_wdata[15:8]  : cur_word[15:8],
    dmem_be[0] ? dmem_wdata[7:0]   : cur_word[7:0]
  };

  always_ff @(posedge clk) begin
    tohost_we_r <= 1'b0;
    if (rst) begin
      mtime <= 64'd0; mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; msip <= 1'b0;
    end else begin
      mtime <= mtime + 64'd1;        // free-running timer
    end
    if (dmem_we) begin
      if (in_dram) dram[dram_idx] <= merged_word;
      else if (in_clint) begin
        if (dmem_addr[15:0]==16'h0000) msip          <= dmem_wdata[0];
        if (dmem_addr[15:0]==16'h4000) mtimecmp[31:0] <= dmem_wdata;
        if (dmem_addr[15:0]==16'h4004) mtimecmp[63:32] <= dmem_wdata;
      end else if (dmem_addr == TOHOST_ADDR) begin
        tohost_r <= dmem_wdata; tohost_we_r <= 1'b1;
      end
    end
  end

  // ---- Debug-Module System-Bus memory path (1-cycle latency) ---------------
  // Independent of the core's dmem port: the hart is halted during SBA, so the
  // two never contend. Supports word access to IMEM and DRAM.
  wire dm_in_dram = (dm_mem_addr >= DRAM_BASE) && (dm_mem_addr < DRAM_BASE + DRAM_WORDS*4);
  wire dm_in_imem = (dm_mem_addr < IMEM_WORDS*4);
  wire [$clog2(DRAM_WORDS)-1:0] dm_dram_idx =
        dm_mem_addr[$clog2(DRAM_WORDS)+1:2] - DRAM_BASE[$clog2(DRAM_WORDS)+1:2];
  wire [$clog2(IMEM_WORDS)-1:0] dm_imem_idx = dm_mem_addr[$clog2(IMEM_WORDS)+1:2];

  always_ff @(posedge clk) begin
    dm_mem_ready <= 1'b0;
    if (dm_mem_valid) begin
      dm_mem_ready <= 1'b1;
      if (dm_mem_write) begin
        if      (dm_in_dram) dram[dm_dram_idx] <= dm_mem_wdata;
        else if (dm_in_imem) imem[dm_imem_idx] <= dm_mem_wdata;
      end else begin
        dm_mem_rdata <= dm_in_dram ? dram[dm_dram_idx] :
                        dm_in_imem ? imem[dm_imem_idx] : 32'h0;
      end
    end
  end
endmodule
