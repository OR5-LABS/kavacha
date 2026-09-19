<div align="center">

# Kavacha

<p align="center">
  <img src="kavacha-banner.png" alt="Kavacha Logo" width="600"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ISA-RV32IMC-green" alt="ISA"/>
  <img src="https://img.shields.io/badge/Extensions-Zicsr-blue" alt="Extensions"/>
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License"/>
  <a href="https://www.linkedin.com/company/open-risc-v/"><img src="https://img.shields.io/badge/LinkedIn-Follow-0077B5" alt="LinkedIn Follow"/></a>
  <a href="https://or5.org"><img src="https://img.shields.io/badge/Visit-or5.org-brightgreen?logo=google-chrome" alt="Visit or5.org"/></a>
</p>
</div>

## About

**Kavacha** (*"armour"* in Sanskrit) is a compact, area-optimized **RV32IMC** processor core.
It executes one instruction at a time through a small multi-cycle finite state machine — no pipeline, no forwarding, and no hazard logic — which keeps the design tiny, deterministic, and straightforward to verify.

Kavacha targets roles where silicon area, power, and security matter more than peak throughput:

-  **Secure boot ROMs and management engines**
-  **Deeply embedded control-plane state machines**
-  **FPGA soft cores for prototyping and production**
-  **IoT microcontrollers with tight area budgets**
-  **Safety-critical subsystems (automotive, industrial, space)**


## Overview

| Property | Value |
|----------|-------|
| ISA | RV32IMC + Zicsr |
| Microarchitecture | Multi-cycle FSM, non-pipelined |
| Privilege modes | Machine; optional User (`SECURE`) |
| Debug | RISC-V External Debug 0.13 over JTAG (DTM + DM; `dmstatus.version` = 2) |
| Bus interfaces | Native memory port + AXI4-Lite |
| Verification | Golden co-simulation, RVFI, self-checks |


---

![Kavacha RV — RISC-V core by OR5 Labs](Kavacha_architecture_README.png)


## Features

### Predictable, Zero-Hazard Execution
A single instruction walks a short FSM (`FETCH → EXEC → {LOAD | MD} → FETCH`).
There is nothing to forward and no hazard to detect — behaviour is completely
deterministic, and correctness is easy to establish.

###  Two-Tier Trust Model
The optional `SECURE` configuration adds a **User privilege mode** and an **8-region Physical Memory Protection (PMP)** unit with **Smepmp** (`mseccfg`) semantics — including Machine Mode Lockdown (MML), Machine Mode Whitelist Policy (MMWP), and Rule Locking Bypass (RLB). Even Machine mode cannot silently escape a strict isolation policy.

###  Register File ECC
The `SECURE` configuration replaces the plain register file with a **SECDED** (single-error-correct, double-error-detect) protected version. Each register is stored with check bits so that a single-bit upset is corrected on read and a double-bit upset is detected — critical for radiation-sensitive and reliability-critical deployments.

###  Verification
The smoke program is co-simulated retire-for-retire against a **golden RV32IM ISA model**; the core exposes an **RVFI** (RISC-V Formal Interface) port with a trace self-check (riscv-formal has not been run yet), and ships self-checking testbenches for the core, the debug module, and the ECC register file.

###  Dual Bus Interfaces
- **Native memory port** — for tightest, zero-latency tightly-coupled memory integration.
- **AXI4-Lite wrapper** — for drop-in integration into standard SoC fabrics, sharing buses with other masters and peripherals.

###  Hardware Debug (RISC-V Debug 0.13)
A JTAG Debug Transport Module and RISC-V Debug Module let **OpenOCD** and **GDB** halt, resume, single-step, inspect registers and CSRs, and read/write memory over the system bus — all out of the box.

###  Compressed Instructions (RVC)
Full support for the **C extension** — 16-bit compressed instructions are transparently expanded to their 32-bit equivalents, improving code density for memory-constrained deployments.

###  Precise Traps & Interrupts
Exceptions (`ECALL`, `EBREAK`, illegal instruction, misaligned access), `MRET`, and timer / software / external interrupt lines are all handled precisely at instruction boundaries.

---

## Configuration Options

Kavacha ships in two build-time configurations, selected by the `SECURE` RTL parameter
or compile-time define `-DKAVACHA_SECURE`:

| Property / Feature | **Default** | **SECURE** |
|---|---|---|
| **Privilege modes** | Machine (M) only | Machine (M) + User (U) |
| **Memory protection** | — | 8-region PMP + Smepmp (`mseccfg`) |
| **Register file** | Plain (32×32-bit) | SECDED ECC protected |
| **Target use case** | Smallest footprint | Isolation & reliability |
| **`misa` U bit** | Not set | Set |
| **Locked PMP regions** | — | Enforced on M-mode too |

### Building each configuration

```bash
# Default configuration (Machine mode only, smallest footprint)
./build.sh

# SECURE configuration (M+U, PMP, ECC)
./build.sh pmp       # User mode + PMP test program
./build.sh epmp      # Smepmp (mseccfg) rules test
./build.sh ecc       # Register-file SECDED ECC unit test
```

---

## FPGA Resource Utilization

> **Target:** Xilinx Artix-7 (Arty A7-100T, `xc7a100tcsg324-1`)
> Post-synthesis & post-implementation results from Vivado 2023.2.

### Standalone Processor Core (`kavacha_core`)

| Configuration | LUTs | FFs | DSPs | BRAMs |
|---------------|------|-----|------|-------|
| **Default** (Machine mode only) | **2,491** | **749** | **4** | **0** |
| **SECURE** (M+U, PMP/ePMP, ECC) | **4,362** | **1,400** | **4** | **0** |

### Full Synthesized SoC (`kavacha_arty_a7`)

| Configuration | LUTs | FFs | DSPs | BRAMs (128 KB) |
|---------------|------|-----|------|----------------|
| **Default** | **2,816** | **1,335** | **4** | **32** |
| **SECURE** | **5,226** | **1,980** | **4** | **32** |

### Core Hierarchical Utilization Breakdown

| Sub-Module / Unit | Description | Default LUTs (FFs) | SECURE LUTs (FFs) |
|-------------------|-------------|--------------------|-------------------|
| `kavacha_regfile` | GPR File (32×32-bit, plain vs SECDED ECC) | 1,403 (0 FFs) | 1,596 (0 FFs) |
| `kavacha_csr` | CSR File (Zicsr, Machine/User, 8-region PMP/ePMP) | 389 (320 FFs) | 2,054 (965 FFs) |
| `kavacha_muldiv` | 32-bit Iterative Multiply & Divide Engine | 437 (237 FFs) | 458 (237 FFs) |
| `kavacha_pmp` | Physical Memory Protection Checker | — | 21 (0 FFs) |
| Control & Exec | FSM, 32-bit ALU, Decoder, RVC Expander, ImmGen | 262 (192 FFs) | 269 (198 FFs) |

---

## Benchmarks

All benchmarks are compiled with:
```
riscv-none-elf-gcc -O2 -march=rv32imc_zicsr -mabi=ilp32
```
Results below are from cycle-accurate simulation, not from an FPGA run.

### CoreMark

| Metric | Simulation (cycle-accurate) |
|--------|-------------------------|
| Iterations | 1,000 |
| Total cycles | 1,234,774,918 |
| Cycles / iteration | 1,234,774.9 |
| CoreMark / MHz | **0.81** |
| Status | ✅ PASS |

### Dhrystone v2.1

| Metric | Simulation (cycle-accurate) |
|--------|-------------------------|
| Iterations | 100,000 |
| Total cycles | 207,900,101 |
| Cycles / iteration | 2,079 |
| Dhrystones / sec / MHz | 481 |
| DMIPS / MHz | **0.274** |
| Status | ✅ PASS |

###  Reproduce It Yourself

All benchmark results are fully reproducible. Run these commands from the repo root:

```bash
# 1. Build the Verilator simulation model
cd bench
make verilator-kavacha

# 2. Run CoreMark
make run-kavacha-coremark ITERATIONS=1000

# 3. Run Dhrystone (from its own directory)
cd ../dhrystone
./run_dhrystone.sh

# 4. Generate a results report
cd ../bench
make report
```

Results are written to `bench/results/` as `.log` files and a summary `report.md`.

---

## Repository Layout

```
kavacha/
├── rtl/                 Core RTL
│   ├── kavacha_core.sv    Multi-cycle control FSM + datapath
│   ├── kavacha_soc.sv     Minimal SoC (IMEM/DRAM, tohost, Debug Module)
│   ├── kavacha_debug.sv   JTAG DTM + RISC-V Debug Module
│   ├── kavacha_axil.sv    AXI4-Lite master / slave / SoC wrapper
│   └── common/            Shared, pre-verified datapath leaf cells
│                          (ALU, multiply/divide, register file, CSR file,
│                           immediate/branch units, decoder, RVC, PMP, ECC)
├── tb/                  Testbenches (smoke, RVFI, debug, AXI-Lite, ECC)
├── tools/               Golden ISA model + co-simulation driver
├── programs/            Test-program builders
├── sw/                  Assembly test programs & bring-up firmware
├── fpga/                FPGA SoC + Arty A7 constraints
├── bench/               Benchmarking suite (CoreMark)
├── dhrystone/           Dhrystone v2.1 benchmark
├── coremark/            CoreMark FPGA runners
└── build.sh             Build & test driver
```

---

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| **Verilator** | 5.018+ | Cycle-accurate RTL simulation for benchmarks |
| **Icarus Verilog** | 12+ | Core simulation (`iverilog` / `vvp`) |
| **Python** | 3.10+ | Test-program builders, co-simulation, report generation |
| **RISC-V GCC** | 13+ (`riscv-none-elf-gcc` or `riscv64-unknown-elf-gcc`) | Compiling firmware and benchmarks |
| **Vivado** | 2023.2+ *(optional)* | FPGA synthesis for Arty A7 |

---

## Build & Verification

### Quick start

```bash
./build.sh          # compile + self-checking smoke test
```

Expected output:
```
[TB] PASS
```

### Full verification suite

```bash
./build.sh cosim    # Co-simulate against the golden ISA model
./build.sh rvfi     # RVFI (formal interface) self-check
./build.sh debug    # JTAG / Debug-Module self-check
./build.sh pmp      # SECURE config: User mode + PMP test program
./build.sh epmp     # SECURE config: Smepmp (mseccfg) rules test
./build.sh ecc      # Register-file SECDED ECC unit test
./build.sh axil     # AXI4-Lite adapter self-check
./build.sh fpga     # FPGA SoC simulation (UART banner + LED activity)
./build.sh clean    # Clean build artifacts
```

| Method | Target | What it proves |
|--------|--------|----------------|
| Smoke test | `sim` | The core runs a real program to completion |
| Golden co-simulation | `cosim` | RTL matches the ISA model retire-for-retire |
| RVFI self-check | `rvfi` | Instruction-level trace conforms to the formal interface |
| Debug self-check | `debug` | The Debug Module halts, inspects, and steps correctly |
| PMP test | `pmp` | User-mode isolation and PMP enforcement |
| Smepmp test | `epmp` | Smepmp (enhanced PMP, `mseccfg`) rules |
| ECC unit test | `ecc` | The register file corrects/detects bit errors |
| AXI4-Lite test | `axil` | Native memory bus to AXI4-Lite protocol conversion |
| FPGA SoC test | `fpga` | Full SoC simulation with synthesizable UART and Debug Module |


## License

Released under the [MIT License](LICENSE) — free for commercial and academic use.
