// ============================================================================
// kavacha_uart.sv  --  Synthesizable 8-N-1 UART with sim-friendly $write hook.
//
// Backward-compatible register map (matches the previous sim-only UART):
//   0x0 W : tx data byte (writes push the byte to the TX shift register)
//   0x0 R : status        bit0 = tx_busy (shifter active)
//                         bit1 = rx_ready (rx_data has a fresh byte)
//                         bit2 = tx_empty (no byte in flight)
//                         bit3 = rx_overrun (sticky until status read)
//   0x4 R : rx data byte  (reading clears rx_ready)
//   0x8 RW: baud_div      (clocks per bit; default = BAUD_DIV_RST)
//
// Parameters:
//   CLK_HZ       -- input clock frequency (default 50_000_000 = 50 MHz)
//   BAUD         -- target baud rate     (default 115_200)
//   BAUD_DIV_RST -- derived divisor      (CLK_HZ / BAUD)
//
// FPGA pins exposed at the SoC top:  serial_tx, serial_rx
// Simulation: when `SIMULATION is defined, writes to tx data ALSO call $write
// so existing testbench harness keeps working with no flag changes.
// ============================================================================

`default_nettype none

module kavacha_uart #(
  parameter int CLK_HZ       = 50_000_000,
  parameter int BAUD         = 115_200,
  parameter int BAUD_DIV_RST = CLK_HZ / BAUD
)(
  input  wire logic       clk,
  input  wire logic       rst,
  // CPU bus (byte access)
  input  wire logic [3:0] addr,
  input  wire logic [7:0] wdata,
  input  wire logic       we,
  input  wire logic       re,
  output logic [7:0]      rdata,
  // Real serial pins (FPGA / tape-out)
  output logic            serial_tx,
  input  wire logic       serial_rx,
  // Interrupts
  output logic            tx_irq,    // pulses when TX shifter empties
  output logic            rx_irq     // pulses when a new byte arrives
);

  // -------------------------------------------------------------------------
  // Runtime baud-rate divisor.
  // -------------------------------------------------------------------------
  logic [15:0] baud_div;

  // -------------------------------------------------------------------------
  // TX path: 10-bit frame (start + 8 data + stop), MSB-first emission of
  // {stop, data[7:0], start} order is wrong -- LSB-first per UART spec.
  // We shift out start, then data[0..7], then stop.
  // -------------------------------------------------------------------------
  logic [9:0]  tx_shift;
  logic [3:0]  tx_bit_count;
  logic [15:0] tx_baud_cnt;
  logic        tx_busy_q;
  logic [7:0]  tx_data_pending;
  logic        tx_load;

  assign tx_load = we && (addr[3:2] == 2'b00) && !tx_busy_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      tx_shift     <= 10'h3FF;
      tx_bit_count <= 4'd0;
      tx_baud_cnt  <= 16'd0;
      tx_busy_q    <= 1'b0;
      serial_tx    <= 1'b1;   // idle high
      tx_irq       <= 1'b0;
    end else begin
      tx_irq <= 1'b0;
      if (tx_load) begin
        // {stop=1, data[7:0], start=0} -- LSB shifted first
        tx_shift     <= {1'b1, wdata, 1'b0};
        tx_bit_count <= 4'd10;
        tx_baud_cnt  <= baud_div - 1;
        tx_busy_q    <= 1'b1;
        // synthesis translate_off
        $write("%c", wdata);
        // synthesis translate_on
      end else if (tx_busy_q) begin
        if (tx_baud_cnt == 16'd0) begin
          serial_tx    <= tx_shift[0];
          tx_shift     <= {1'b1, tx_shift[9:1]};
          tx_bit_count <= tx_bit_count - 4'd1;
          tx_baud_cnt  <= baud_div - 1;
          if (tx_bit_count == 4'd1) begin
            tx_busy_q <= 1'b0;
            tx_irq    <= 1'b1;
          end
        end else begin
          tx_baud_cnt <= tx_baud_cnt - 16'd1;
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // RX path: oversample-by-1 (sample at mid-bit using baud_div/2 phase).
  // Detect falling edge of serial_rx as start bit.
  // -------------------------------------------------------------------------
  logic [1:0]  rx_sync;
  logic        rx_busy_q;
  logic [3:0]  rx_bit_count;
  logic [15:0] rx_baud_cnt;
  logic [7:0]  rx_shift;
  logic [7:0]  rx_data_q;
  logic        rx_ready_q;
  logic        rx_overrun_q;

  always_ff @(posedge clk) begin
    if (rst) rx_sync <= 2'b11;
    else     rx_sync <= {rx_sync[0], serial_rx};
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      rx_busy_q    <= 1'b0;
      rx_bit_count <= 4'd0;
      rx_baud_cnt  <= 16'd0;
      rx_shift     <= 8'h0;
      rx_data_q    <= 8'h0;
      rx_ready_q   <= 1'b0;
      rx_overrun_q <= 1'b0;
      rx_irq       <= 1'b0;
    end else begin
      rx_irq <= 1'b0;
      // Clear rx_ready when CPU reads RX data
      if (re && addr[3:2] == 2'b01) rx_ready_q <= 1'b0;
      // Status read clears overrun sticky bit
      if (re && addr[3:2] == 2'b00) rx_overrun_q <= 1'b0;

      if (!rx_busy_q) begin
        if (rx_sync[1] == 1'b0) begin
          // Saw start bit; wait 1.5 bit times to sample data[0] mid-bit
          rx_busy_q    <= 1'b1;
          rx_bit_count <= 4'd8;
          rx_baud_cnt  <= {1'b0, baud_div[15:1]} + baud_div - 1;
        end
      end else begin
        if (rx_baud_cnt == 16'd0) begin
          if (rx_bit_count != 4'd0) begin
            rx_shift     <= {rx_sync[1], rx_shift[7:1]};
            rx_bit_count <= rx_bit_count - 4'd1;
            rx_baud_cnt  <= baud_div - 1;
          end else begin
            // Stop bit time -- commit byte
            rx_busy_q <= 1'b0;
            rx_data_q <= rx_shift;
            if (rx_ready_q) rx_overrun_q <= 1'b1;
            rx_ready_q <= 1'b1;
            rx_irq     <= 1'b1;
          end
        end else begin
          rx_baud_cnt <= rx_baud_cnt - 16'd1;
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // baud_div register (0x8)
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) baud_div <= BAUD_DIV_RST[15:0];
    else if (we && addr[3:2] == 2'b10) baud_div <= {wdata, baud_div[7:0]};  // low byte each write
  end

  // -------------------------------------------------------------------------
  // Read mux
  // -------------------------------------------------------------------------
  always_comb begin
    case (addr[3:2])
      2'b00:   rdata = {4'b0, rx_overrun_q, ~tx_busy_q, rx_ready_q, tx_busy_q};
      2'b01:   rdata = rx_data_q;
      2'b10:   rdata = baud_div[7:0];
      default: rdata = 8'h0;
    endcase
  end

endmodule

`default_nettype wire
