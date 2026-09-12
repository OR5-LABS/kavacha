# Configuration Reference

Kavacha is configured through RTL parameters and a compile-time define. This
page collects the knobs in one place.

## Configurations

| Configuration | Privilege | Memory protection | Register file |
|---------------|-----------|-------------------|---------------|
| **Default** | Machine only | — | plain |
| **`SECURE`** | Machine + User | 8-region PMP + ePMP | SECDED ECC |

Select the secure tier with the `SECURE` parameter on `kavacha_core` /
`kavacha_soc`, or globally at compile time with `-DKAVACHA_SECURE`.

## Core parameters (`kavacha_core`)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `RESET_PC` | `0x0000_0000` | address of the first instruction after reset |
| `SECURE` | `0` | add User mode + PMP + ePMP + register-file ECC |

## SoC parameters (`kavacha_soc`)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `IMEM_WORDS` | `8192` | instruction-memory depth (32-bit words) |
| `DRAM_WORDS` | `8192` | data-RAM depth (32-bit words) |
| `DRAM_BASE` | `0x8000_0000` | base address of data RAM |
| `TOHOST_ADDR` | `0x2000_0000` | address of the `tohost` control word |
| `SECURE` | from `-DKAVACHA_SECURE` | enable the secure configuration |

## Toolchain overrides

The build drivers honour environment variables so you can point at a specific
install:

| Variable | Used by | Purpose |
|----------|---------|---------|
| `IVERILOG` | `build.sh`, `build.ps1` | path to the `iverilog` binary |
| `VVP` | `build.sh`, `build.ps1` | path to the `vvp` binary |
| `RISCV_TC` | `build.sh` | RISC-V GCC toolchain `bin/` directory |

## Build actions

| Action | Effect |
|--------|--------|
| `sim` (default) | compile core + SoC, run the smoke test |
| `cosim` | smoke test + golden ISA co-simulation |
| `rvfi` | RVFI formal-interface self-check |
| `debug` | JTAG / Debug-Module self-check |
| `pmp` | `SECURE` build running the PMP test program |
| `epmp` | `SECURE` build exercising the ePMP rules |
| `ecc` | register-file SECDED ECC unit test |
| `fpga` | FPGA SoC simulation (UART + LEDs) |
| `clean` | remove build artifacts |
