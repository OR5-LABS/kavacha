// ============================================================================
// kavacha_fpga.sv — Synthesizable FPGA SoC for Kavacha (RV32IMC).
//
// Self-contained, board-independent SoC for real-hardware bring-up:
//   * Unified distributed-RAM (LUTRAM, async/combinational read) holding code +
//     data + stack, $readmemh-initialised from MEMFILE at synthesis. Distributed
//     RAM keeps the zero-latency read the core expects (block RAM would need the
//     mem_stall path); fine for a demo-sized image, bump MEM_WORDS as needed.
//   * Real synthesizable UART (synthesizable 8-N-1) @ 0x1000_0000.
//   * 8 user LEDs @ 0x2000_1000; tohost @ 0x2000_0000 (sim/bring-up handshake).
//   * Minimal CLINT (msip/mtime/mtimecmp) @ 0x0200_0000 for timer/soft IRQ.
//   * RISC-V Debug Module + JTAG DTM (kavacha_debug) — drive from OpenOCD.
//
// Address map:
//   0x0000_0000.. : RAM (MEM_WORDS words)
//   0x0200_0000   : CLINT
//   0x1000_0000   : UART (16 bytes)
//   0x2000_0000   : tohost
//   0x2000_1000   : LED register (low 8 bits)
// ============================================================================
`include "kavacha_pkg.sv"
`default_nettype none

module kavacha_fpga
  import kavacha_pkg::*;
#(
  parameter int CLK_HZ     = 50_000_000,
  parameter int UART_BAUD  = 115_200,
  parameter int MEM_WORDS  = 4096,          // 16 KB unified RAM (distributed)
  parameter     MEMFILE    = ""             // firmware .mem ($readmemh) for synthesis
)(
  input  wire        clk,
  input  wire        rst,
  // JTAG debug (tie low if unused)
  input  wire        tck,
  input  wire        tms,
  input  wire        tdi,
  output wire        tdo,
  // board I/O
  output reg  [7:0]  leds,
  output wire        serial_tx,
  input  wire        serial_rx,
  // optional bring-up handshake
  output reg  [31:0] tohost,
  output reg         tohost_we
);
  localparam int AW = $clog2(MEM_WORDS);

  // ---- unified program/data RAM (distributed, async read) ------------------
  (* ram_style = "distributed" *) reg [31:0] mem [0:MEM_WORDS-1];
  initial if (MEMFILE != "") $readmemh(MEMFILE, mem);

  // ---- core <-> bus --------------------------------------------------------
  wire [31:0] imem_addr, imem_rdata;
  wire [31:0] dmem_addr, dmem_wdata;
  wire        dmem_re, dmem_we;
  wire [3:0]  dmem_be;
  logic [31:0] dmem_rdata;

  // ---- debug module wires --------------------------------------------------
  wire        dbg_haltreq, dbg_resumereq, dbg_halted, ndmreset;
  wire        dbg_ar_valid, dbg_ar_write, dbg_ar_csr, dbg_ar_done;
  wire [11:0] dbg_ar_regno;
  wire [31:0] dbg_ar_wdata, dbg_ar_rdata;
  wire        dm_mem_valid, dm_mem_write;
  wire [31:0] dm_mem_addr, dm_mem_wdata;
  logic [31:0] dm_mem_rdata;
  logic        dm_mem_ready;

  wire core_rst = rst | ndmreset;

  // ---- CLINT ---------------------------------------------------------------
  reg  [63:0] mtime, mtimecmp;
  reg         msip;
  wire        irq_timer = (mtime >= mtimecmp);
  wire        irq_soft  = msip;

  kavacha_core u_core (
    .clk(clk), .rst(core_rst),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
    .dmem_be(dmem_be), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
    .irq_timer(irq_timer), .irq_soft(irq_soft), .irq_ext(1'b0),
    .mem_stall(1'b0),
    .retire_valid(), .retire_pc(), .retire_instr(),
    .retire_rd_we(), .retire_rd(), .retire_rd_val(),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done)
  );

  kavacha_debug u_dbg (
    .clk(clk), .rst(rst), .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq),
    .ndmreset(ndmreset), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done),
    .dm_mem_valid(dm_mem_valid), .dm_mem_write(dm_mem_write),
    .dm_mem_addr(dm_mem_addr), .dm_mem_wdata(dm_mem_wdata),
    .dm_mem_rdata(dm_mem_rdata), .dm_mem_ready(dm_mem_ready)
  );

  // ---- instruction fetch (async read) --------------------------------------
  assign imem_rdata = mem[imem_addr[AW+1:2]];

  // ---- data-bus decode -----------------------------------------------------
  wire in_ram    = (dmem_addr < MEM_WORDS*4);
  wire uart_sel  = (dmem_addr[31:16] == 16'h1000);
  wire clint_sel = (dmem_addr[31:16] == 16'h0200);
  wire led_sel   = (dmem_addr == 32'h2000_1000);
  wire tohost_sel= (dmem_addr == 32'h2000_0000);
  wire [AW-1:0] didx = dmem_addr[AW+1:2];

  // ---- UART ----------------------------------------------------------------
  wire [7:0] uart_rdata; wire uart_tx_irq, uart_rx_irq;
  kavacha_uart #(.CLK_HZ(CLK_HZ), .BAUD(UART_BAUD)) u_uart (
    .clk(clk), .rst(rst), .addr(dmem_addr[3:0]), .wdata(dmem_wdata[7:0]),
    .we(dmem_we && uart_sel), .re(dmem_re && uart_sel), .rdata(uart_rdata),
    .serial_tx(serial_tx), .serial_rx(serial_rx),
    .tx_irq(uart_tx_irq), .rx_irq(uart_rx_irq)
  );

  // ---- CLINT read words ----------------------------------------------------
  wire [31:0] clint_rdata =
        (dmem_addr[15:0]==16'h0000) ? {31'b0, msip}     :
        (dmem_addr[15:0]==16'h4000) ? mtimecmp[31:0]    :
        (dmem_addr[15:0]==16'h4004) ? mtimecmp[63:32]   :
        (dmem_addr[15:0]==16'hBFF8) ? mtime[31:0]       :
        (dmem_addr[15:0]==16'hBFFC) ? mtime[63:32]      : 32'h0;

  // ---- data read mux -------------------------------------------------------
  always_comb begin
    if      (uart_sel)  dmem_rdata = {24'h0, uart_rdata};
    else if (clint_sel) dmem_rdata = clint_rdata;
    else if (in_ram)    dmem_rdata = mem[didx];
    else                dmem_rdata = 32'h0;
  end

  // ---- writes (core data port) + CLINT/LED/tohost --------------------------
  always_ff @(posedge clk) begin
    tohost_we <= 1'b0;
    if (rst) begin
      mtime <= 64'd0; mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; msip <= 1'b0; leds <= 8'h0;
    end else begin
      mtime <= mtime + 64'd1;

      // RAM write: Debug-Module System-Bus write (priority) or CPU core write
      if (dm_mem_valid && dm_mem_write && (dm_mem_addr < MEM_WORDS*4)) begin
        mem[dm_mem_addr[AW+1:2]] <= dm_mem_wdata;
      end else if (dmem_we && in_ram) begin
        if (dmem_be[0]) mem[didx][7:0]   <= dmem_wdata[7:0];
        if (dmem_be[1]) mem[didx][15:8]  <= dmem_wdata[15:8];
        if (dmem_be[2]) mem[didx][23:16] <= dmem_wdata[23:16];
        if (dmem_be[3]) mem[didx][31:24] <= dmem_wdata[31:24];
      end

      // CLINT / LED / tohost writes
      if (dmem_we) begin
        if (!in_ram) begin
          if (clint_sel) begin
            if (dmem_addr[15:0]==16'h0000) msip           <= dmem_wdata[0];
            if (dmem_addr[15:0]==16'h4000) mtimecmp[31:0] <= dmem_wdata;
            if (dmem_addr[15:0]==16'h4004) mtimecmp[63:32]<= dmem_wdata;
          end else if (led_sel)   leds <= dmem_wdata[7:0];
          else if (tohost_sel) begin tohost <= dmem_wdata; tohost_we <= 1'b1; end
        end
      end
    end
  end

  // ---- Debug-Module System-Bus read path (1-cycle) -------------------------
  always_ff @(posedge clk) begin
    dm_mem_ready <= 1'b0;
    if (dm_mem_valid) begin
      dm_mem_ready <= 1'b1;
      if (!dm_mem_write && (dm_mem_addr < MEM_WORDS*4))
        dm_mem_rdata <= mem[dm_mem_addr[AW+1:2]];
    end
  end
endmodule

`default_nettype wire
