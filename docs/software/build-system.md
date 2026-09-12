# Firmware Toolchain & Build Driver

Kavacha provides a unified build driver script (**`./build.sh`**) and C software build pipeline (`firmware/`) supporting the official **`riscv32-unknown-elf-gcc`** toolchain.

---

## 1. Toolchain Installation & Requirements

To compile firmware and run verification testbenches, the system requires the following tools:

| Tool / Package | Required Version | Functional Role |
|----------------|:----------------:|-----------------|
| **GCC Toolchain** | `riscv32-unknown-elf-gcc` (v10.0+) | Compiles C/C++ source files targeting `-march=rv32imc -mabi=ilp32`. |
| **Binutils** | `riscv32-unknown-elf-objcopy` / `objdump` | Extracts binary images, memory hex files, and disassembly listings. |
| **Python** | Python 3.8+ | Executes Cocotb test suites and verification scripts. |
| **Verilator** | Verilator 5.0+ | Compiles SystemVerilog RTL into C++ simulator executable. |
| **MkDocs** | `mkdocs-material` | Builds and serves documentation. |

---

## 2. Master Build Driver (`./build.sh`) Commands

The `./build.sh` script provides a single unified CLI for all software, hardware, simulation, and documentation tasks:

```bash
# -----------------------------------------------------------------------------
# Kavacha Master Build Driver CLI Options
# -----------------------------------------------------------------------------

./build.sh test      # Runs Cocotb unit test suite via Verilator
./build.sh isa       # Runs official RISC-V Architectural Compliance suite (riscv-tests)
./build.sh pmp       # Runs 8-region PMP verification suite under SECURE=1
./build.sh epmp      # Runs ePMP (mseccfg) verification suite under SECURE=1
./build.sh ecc       # Runs SECDED ECC register file unit testbench
./build.sh synth     # Runs Vivado FPGA synthesis & generates area/timing reports
./build.sh docs      # Launches MkDocs local documentation server at http://127.0.0.1:8000
./build.sh clean     # Removes build artifacts, object files, and simulation dumps
```

---

## 3. Linker Script (`firmware/link.ld`)

The linker script aligns code and data sections to match Kavacha's SoC memory map:

```ld
/* Kavacha SoC Reference Linker Script (firmware/link.ld) */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 128K
}

SECTIONS {
  .text : {
    *(.text.init)
    *(.text*)
  } > RAM

  .rodata : {
    *(.rodata*)
  } > RAM

  .data : {
    *(.data*)
  } > RAM

  .bss : {
    *(.bss*)
  } > RAM

  /* Stack Top Setup */
  .stack (NOLOAD) : {
    . = ALIGN(16);
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
  } > RAM
}
```

---

## 4. Firmware Hex Conversion Pipeline

To load C programs into `$readmemh` memory models for simulation or synthesis, the build pipeline converts the output ELF into a 32-bit hex word file (`firmware.mem`):

```bash
# 1. Compile C and Assembly source files
riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -O2 -T firmware/link.ld \
    firmware/start.S firmware/main.c -o build/firmware.elf -nostdlib

# 2. Extract raw binary
riscv32-unknown-elf-objcopy -O binary build/firmware.elf build/firmware.bin

# 3. Convert binary to 32-bit hex format for SystemVerilog $readmemh
python3 scripts/bin2hex.py build/firmware.bin build/firmware.mem

# 4. Generate disassembly listing for debugging
riscv32-unknown-elf-objdump -d build/firmware.elf > build/firmware.dis
```
