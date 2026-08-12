#!/usr/bin/env bash
# build_fpga_hello.sh — assemble the FPGA bring-up demo into firmware.mem
# ($readmemh, one 32-bit word per line) for kavacha_fpga / takshaka_fpga.
set -euo pipefail
cd "$(dirname "$0")"
TC="${RISCV_TC:-../../toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
GCC="${GCC:-$TC/riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-$TC/riscv-none-elf-objcopy}"

if [[ ! -x "$GCC" ]]; then
  if command -v riscv64-unknown-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv64-unknown-elf-gcc)
    OBJCOPY=$(command -v riscv64-unknown-elf-objcopy)
  elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv32-unknown-elf-gcc)
    OBJCOPY=$(command -v riscv32-unknown-elf-objcopy)
  elif command -v riscv-none-elf-gcc &>/dev/null; then
    GCC=$(command -v riscv-none-elf-gcc)
    OBJCOPY=$(command -v riscv-none-elf-objcopy)
  fi
fi

OUT="${1:-firmware.mem}"


"$GCC" -march=rv32imc -mabi=ilp32 -nostdlib -nostartfiles -fno-pic \
       -Wl,--no-relax -T fpga_hello.ld fpga_hello.S -o fpga_hello.elf
"$OBJCOPY" -O binary fpga_hello.elf fpga_hello.bin
python bin2hex.py fpga_hello.bin "$OUT"
echo "wrote $OUT"
