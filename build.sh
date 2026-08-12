#!/usr/bin/env bash
# ============================================================================
# build.sh — build & run Kavacha under Icarus Verilog.
#
#   ./build.sh [sim|cosim|rvfi|debug|pmp|epmp|ecc|fpga|clean]
#
#   sim    (default) compile the core + SoC and run the self-checking smoke test
#   cosim  run smoke, then co-simulate against the golden RV32IM ISA model
#   rvfi   build the RVFI (riscv-formal interface) self-check
#   debug  build the JTAG / Debug-Module self-check
#   pmp    build the SECURE config (U-mode + PMP) and run the PMP test program
#   epmp   as pmp, exercising the ePMP (mseccfg) rules
#   ecc    build the register-file SECDED ECC unit test
#   fpga   build the FPGA SoC sim (UART banner + LED blink) from firmware.mem
#   clean  remove build artifacts
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

IVL="${IVERILOG:-iverilog}"
VVP="${VVP:-vvp}"
ACTION="${1:-sim}"

R=rtl            # kavacha core + SoC
C=rtl/common     # shared datapath leaf cells

# Every simulation build needs the same leaf-cell set.
CELLS="$C/kavacha_pkg.sv $C/kavacha_alu.sv $C/kavacha_regfile.sv \
       $C/kavacha_muldiv.sv $C/kavacha_csr.sv $C/kavacha_rvc.sv \
       $C/kavacha_immgen.sv $C/kavacha_branch.sv $C/kavacha_decode.sv $C/kavacha_pmp.sv"
CORE="$R/kavacha_core.sv $R/kavacha_debug.sv $R/kavacha_soc.sv"

if [[ "$ACTION" == "clean" ]]; then
  rm -rf sim programs/build/*.hex *.vcd
  echo "Cleaned."
  exit 0
fi
mkdir -p sim programs/build

# ---- register-file ECC (SECDED) unit test ---------------------------------
if [[ "$ACTION" == "ecc" ]]; then
  echo "Building register-file SECDED ECC unit test..."
  "$IVL" -g2012 -I "$C" -o sim/tb_regfile_ecc \
    "$C/kavacha_pkg.sv" "$C/kavacha_regfile_ecc.sv" tb/tb_regfile_ecc.sv
  "$VVP" sim/tb_regfile_ecc
  exit 0
fi

# ---- SECURE config: U-mode + PMP / ePMP -----------------------------------
if [[ "$ACTION" == "pmp" || "$ACTION" == "epmp" ]]; then
  TC="${RISCV_TC:-../toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
  GCC="$TC/riscv-none-elf-gcc"
  OBJCOPY="$TC/riscv-none-elf-objcopy"
  SRCASM=sw/pmp_test.S; [[ "$ACTION" == "epmp" ]] && SRCASM=sw/epmp_test.S
  if [[ -x "$GCC" ]]; then
    echo "Assembling $SRCASM ..."
    "$GCC" -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding \
           -Wl,-Ttext=0 "$SRCASM" -o programs/build/pmp.elf
    "$OBJCOPY" -O binary -j .text programs/build/pmp.elf programs/build/pmp.bin
    python sw/bin2hex.py programs/build/pmp.bin programs/build/pmp.hex
  else
    echo "No RISC-V toolchain found; using the prebuilt programs/build/pmp.hex."
  fi
  echo "Building Kavacha SECURE sim (U-mode + PMP + ePMP + regfile ECC)..."
  "$IVL" -g2012 -DKAVACHA_SECURE -I "$C" -I "$R" -o sim/tb_kavacha \
    $CELLS "$C/kavacha_regfile_ecc.sv" $CORE tb/tb_kavacha.sv
  echo "Running $ACTION test on Kavacha..."
  "$VVP" sim/tb_kavacha +IMEM=programs/build/pmp.hex
  exit 0
fi

# ---- default: compile + smoke ---------------------------------------------
python programs/build_smoke.py
echo "Compiling..."
"$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_kavacha $CELLS $CORE tb/tb_kavacha.sv
echo "Running smoke..."
"$VVP" sim/tb_kavacha +IMEM=programs/build/smoke.hex

# ---- golden co-simulation --------------------------------------------------
if [[ "$ACTION" == "cosim" ]]; then
  echo "Co-simulating against the golden RV32IM ISA model..."
  VVP="$VVP" python tools/cosim.py \
      --hex programs/build/smoke.hex --sim sim/tb_kavacha
fi

# ---- RVFI (riscv-formal interface) self-check -----------------------------
if [[ "$ACTION" == "rvfi" ]]; then
  echo "Building RVFI self-check..."
  "$IVL" -g2012 -DRISCV_FORMAL -I "$C" -I "$R" -o sim/tb_kavacha_rvfi \
    $CELLS $CORE tb/tb_kavacha_rvfi.sv
  "$VVP" sim/tb_kavacha_rvfi +IMEM=programs/build/smoke.hex
fi

# ---- JTAG / Debug-Module self-check ---------------------------------------
if [[ "$ACTION" == "debug" ]]; then
  echo "Building JTAG / Debug-Module self-check..."
  "$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_kavacha_debug \
    $CELLS $CORE tb/tb_kavacha_debug.sv
  "$VVP" sim/tb_kavacha_debug +IMEM=programs/build/smoke.hex
fi

# ---- FPGA SoC sim (UART banner + LED blink) -------------------------------
if [[ "$ACTION" == "fpga" ]]; then
  echo "Building FPGA SoC sim..."
  [[ -f sw/firmware.mem ]] || (cd sw && bash build_fpga_hello.sh)
  "$IVL" -g2012 -DSIMULATION -I "$C" -I "$R" -o sim/tb_kavacha_fpga \
    $CELLS "$R/kavacha_core.sv" "$R/kavacha_debug.sv" \
    fpga/common/kavacha_uart.sv fpga/kavacha_fpga.sv fpga/tb_kavacha_fpga.sv
  "$VVP" sim/tb_kavacha_fpga
fi
