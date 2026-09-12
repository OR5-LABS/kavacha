# ASIC Synthesis & OpenLane / Yosys

Kavacha is fully synthesizable to ASIC technology cells using open-source EDA toolchains (**Yosys**, **OpenROAD**, and **OpenLane**) targeting the **SkyWater 130nm High-Density (sky130_fd_sc_hd)** PDK.

---

## 1. ASIC Post-Layout Gate Count & Area Summary (Sky130 130nm PDK)

Synthesis performed using Yosys / OpenLane 2 on `sky130_fd_sc_hd` standard cell library ($V_{DD} = 1.8\text{V}$, Typical Corner $25^\circ\text{C}$):

| Configuration | Standard Cell Count | Silicon Die Area ($\text{mm}^2$) | Equivalent Gate Count (NAND2) | Max Clock Frequency |
|---------------|:-------------------:|:-------------------------------:|:-----------------------------:|:-------------------:|
| **Kavacha Core Default (`SECURE = 0`)** | **~18,400 cells** | **0.14 mm$^2$** | **~19,200 GE** | **80.0 MHz** |
| **Kavacha Core SECURE (`SECURE = 1`)** | **~34,200 cells** | **0.26 mm$^2$** | **~35,800 GE** | **70.0 MHz** |

---

## 2. OpenLane Configuration File (`openlane/config.json`)

To run a complete GDSII tapeout flow via OpenLane:

```json
{
  "DESIGN_NAME": "kavacha_core",
  "VERILOG_FILES": [
    "dir::../rtl/common/kavacha_pkg.sv",
    "dir::../rtl/common/kavacha_decode.sv",
    "dir::../rtl/common/kavacha_rvc.sv",
    "dir::../rtl/common/kavacha_immgen.sv",
    "dir::../rtl/common/kavacha_alu.sv",
    "dir::../rtl/common/kavacha_branch.sv",
    "dir::../rtl/common/kavacha_muldiv.sv",
    "dir::../rtl/common/kavacha_regfile.sv",
    "dir::../rtl/common/kavacha_csr.sv",
    "dir::../rtl/kavacha_core.sv"
  ],
  "CLOCK_PORT": "clk",
  "CLOCK_PERIOD": 12.5,
  "DESIGN_IS_CORE": 1,
  "FP_CORE_UTIL": 45,
  "PL_TARGET_DENSITY": 0.50,
  "SYNTH_MAX_FANOUT": 10,
  "PDK": "sky130A",
  "STD_CELL_LIBRARY": "sky130_fd_sc_hd"
}
```

---

## 3. Standalone Yosys Area Synthesis Script (`scripts/yosys_synth.tcl`)

Kavacha includes a standalone Yosys TCL script to evaluate cell count and gate equivalents without installing the full OpenLane flow:

```tcl
# Yosys Open-Source Synthesis Script (scripts/yosys_synth.tcl)
read_verilog -sv rtl/common/*.sv
read_verilog -sv rtl/*.sv

# Elaborate Top Module
hierarchy -top kavacha_core

# Run Generic Synthesis Passes
synth -top kavacha_core

# Map to Generic Gate Primitives
techmap
opt

# Print Gate Count & Equivalent Gate Summary
stat -tech cmos
```

### Execution Command
```bash
yosys -s scripts/yosys_synth.tcl
```
