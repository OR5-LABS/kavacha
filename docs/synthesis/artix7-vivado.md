# Xilinx Artix-7 Synthesis & Vivado

Kavacha is optimized for FPGA soft-core deployment, targeting AMD Xilinx **Artix-7** FPGAs (e.g. Digilent Arty A7-35T / A7-100T, `xc7a35tcsg324-1`). 

The core synthesizes cleanly in Vivado with zero warning latch inferences, compact LUT utilization, and a deterministic 100 MHz system clock.

---

## 1. Post-Synthesis Resource Utilization & Timing Summary

Synthesis runs performed on Vivado 2022.2 targeting `xc7a35tcsg324-1` ($V_{CC} = 1.0\text{V}$, Speed Grade `-1`):

| Target Configuration | LUTs | Flip-Flops (FF) | Block RAM (RAMB36) | DSP48E1 Slices | $F_{\max}$ (Max Freq) |
|----------------------|:----:|:---------------:|:------------------:|:--------------:|:--------------------:|
| **Kavacha Core Default (`SECURE = 0`)** | **2,491** | **749** | **0** | **0** | **100.0 MHz** |
| **Kavacha Core SECURE (`SECURE = 1`)** | **4,362** | **1,400** | **0** | **0** | **90.0 MHz** |
| **Reference SoC Default (`SECURE = 0`)** | **2,816** | **1,335** | **32** (128 KB) | **0** | **100.0 MHz** |
| **Reference SoC SECURE (`SECURE = 1`)** | **5,226** | **1,980** | **32** (128 KB) | **0** | **85.0 MHz** |

---

## 2. Non-Project Mode Vivado TCL Script (`scripts/synth.tcl`)

Kavacha includes a fully automated Vivado TCL synthesis script (`scripts/synth.tcl`) runnable in batch mode without opening the Vivado GUI:

```tcl
# Xilinx Vivado Non-Project Synthesis Script (scripts/synth.tcl)
set target_part "xc7a35tcsg324-1"
set top_module  "kavacha_soc"

# 1. Read SystemVerilog Source Files
read_verilog -sv [glob rtl/common/*.sv]
read_verilog -sv [glob rtl/*.sv]

# 2. Read Timing Constraints
read_xdc constraints/arty_a7.xdc

# 3. Run Synthesis Engine
synth_design -top $top_module -part $target_part -flatten_hierarchy rebuilt

# 4. Write Post-Synthesis Reports
report_utilization -file build/synth_utilization.txt
report_timing_summary -file build/synth_timing.txt

# 5. Generate Bitstream
opt_design
place_design
route_design
write_bitstream -force build/kavacha_soc.bit
```

---

## 3. Physical Timing Constraints (`constraints/arty_a7.xdc`)

```tcl
## Primary 100 MHz Oscillator Input Clock Pin (Arty A7-35T E3)
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports { clk }];

## System Reset Input Pin (Active Low Push Button RESET C2)
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

## UART Console Pins (FTDI Chip USB-UART Bridge)
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_tx_o }];
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { uart_rx_i }];

## User LEDs (LED0 .. LED3)
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports { leds_o[0] }];
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports { leds_o[1] }];
set_property -dict { PACKAGE_PIN T9 IOSTANDARD LVCMOS33 } [get_ports { leds_o[2] }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { leds_o[3] }];
```

---

## 4. Running Synthesis & Bitstream Generation (`build.sh`)

Synthesis is triggered via the unified `build.sh` build script:

```bash
# Run Vivado synthesis & report area / timing
./build.sh synth
```

Upon completion, synthesis summaries are saved to:
* **Area Report:** `build/synth_utilization.txt`
* **Timing Report:** `build/synth_timing.txt`
* **Bitstream Output:** `build/kavacha_soc.bit`
