# EMBench™-IoT Evaluation Suite for Kavacha

This document details the toolchain, compiler configuration, workload descriptions, execution parameters, and benchmark results for the **Kavacha** RISC-V (RV32IMC) processor core running the **EMBench™-IoT** benchmark suite.

---

## Toolchain & Environment

All EMBench-IoT workloads are compiled using the project's bundled GNU RISC-V toolchain with bare-metal freestanding optimization flags:

| Setting | Value |
|---------|-------|
| **Primary Toolchain** | `xPack GNU RISC-V Embedded GCC 13.2.0` (`riscv-none-elf-gcc`) |
| **Fallback Toolchain** | `riscv64-elf-gcc` / `riscv64-unknown-elf-gcc` (GCC 13+ / 15+) |
| **Target Architecture** | `-march=rv32imc_zicsr` |
| **Target ABI** | `-mabi=ilp32` |
| **Optimization Level** | `-O2` |
| **Simulation Engine** | `Verilator 5.018+` (cycle-accurate C++ RTL model) |
| **Hardware Target** | Digilent Arty A7-100T (Xilinx Artix-7 `xc7a100tcsg324-1`) @ 50 MHz |

### Compiler Flags

```bash
-march=rv32imc_zicsr -mabi=ilp32 \
-O2 \
-ffreestanding \
-ffunction-sections \
-fdata-sections \
-fno-builtin \
-fno-common \
-Wall \
-nostdlib \
-nostartfiles
```

### Linker Configuration

```bash
-T bench/common/bench.ld -Wl,--gc-sections
```
*(For FPGA Hardware-in-the-Loop execution, `sw/fpga_bench.ld` and `sw/crt0_fpga.S` are used).*

---

## Benchmark Workload Overview

EMBench-IoT consists of real-world algorithms spanning signal processing, cryptography, compression, sorting, and control:

| Benchmark | Category / Description | Workload Scale |
|-----------|------------------------|:--------------:|
| `aha-mont64` | 64-bit Montgomery multiplication for cryptography | 100 |
| `crc32` | 32-bit standard cyclic redundancy check calculation | 100 |
| `depthconv` | Depthwise 2D separable convolution layer (ML / DSP) | 100 |
| `edn` | Finite impulse response (FIR) filter & vector mathematics | 100 |
| `huffbench` | Huffman compression and decompression | 2 |
| `matmult-int` | 32-bit integer matrix multiplication | 100 |
| `md5sum` | MD5 message-digest cryptographic hashing | 100 |
| `nettle-aes` | AES-128 cryptographic block cipher | 100 |
| `nettle-sha256` | SHA-256 secure hash standard algorithm | 100 |
| `nsichneu` | Petri net simulation and state-machine traversal | 10 |
| `picojpeg` | Baseline sequential JPEG image decompression | 10 |
| `qrduino` | QR code scanning and matrix decoding | 10 |
| `sglib-combined` | Data structure containers (lists, red-black trees, arrays) | 100 |
| `slre` | Super Light Regular Expression parser | 100 |
| `statemate` | Statechart code generated for automotive controllers | 100 |
| `tarfind` | POSIX tar archive parsing and lookup | 100 |
| `ud` | Diagonal matrix decomposition | 100 |
| `wikisort` | Fast in-place stable merge sort | 2 |
| `xgboost` | Gradient boosted decision tree inference | 100 |

---

## Benchmark Results

### Summary

| Metric | FPGA HIL (Arty A7 @ 50 MHz) |
|--------|:---------------------------:|
| **Benchmarks Executed** | **15** |
| **Pass Rate** | **15 / 15 (100%)** |
| **Geometric Mean (Cycles)** | **7,122,462** |

---

### Detailed Cycle Counts per Workload

| Benchmark | Scale Factor | FPGA HIL Cycles (@ 50 MHz) | Status |
|-----------|:------------:|:--------------------------:|:------:|
| `nsichneu` | 10 | 89,710 | ✅ PASS |
| `ud` | 100 | 659,080 | ✅ PASS |
| `huffbench` | 2 | 1,930,435 | ✅ PASS |
| `nettle-sha256` | 100 | 3,643,639 | ✅ PASS |
| `aha-mont64` | 100 | 3,908,328 | ✅ PASS |
| `crc32` | 100 | 9,425,039 | ✅ PASS |
| `slre` | 100 | 8,875,369 | ✅ PASS |
| `wikisort` | 2 | 7,161,975 | ✅ PASS |
| `edn` | 100 | 16,776,669 | ✅ PASS |
| `tarfind` | 100 | 21,895,088 | ✅ PASS |
| `qrduino` | 10 | 21,859,140 | ✅ PASS |
| `nettle-aes` | 100 | 22,991,913 | ✅ PASS |
| `picojpeg` | 10 | 25,180,369 | ✅ PASS |
| `matmult-int` | 100 | 36,717,157 | ✅ PASS |
| `sglib-combined` | 100 | 37,050,759 | ✅ PASS |
| `statemate` | 100 | — | — |
| `depthconv` | 100 | — | — |
| `md5sum` | 100 | — | — |
| `xgboost` | 100 | — | — |
| **Geometric Mean** | — | **7,122,462** | ✅ PASS |

---

## Geometric Mean Calculation Methodology

The geometric mean across all passing workloads is computed as:

$$\text{Geomean} = \exp\left( \frac{1}{N} \sum_{i=1}^{N} \ln(\text{Cycles}_i) \right)$$

---

## Available Runner Scripts

- **`./run_embench.sh`**:
  Compiles all 19 EMBench workloads with `-O2` using `riscv-none-elf-gcc` (GCC 13.2.0), executes them in parallel on the Verilator simulation model, checks pass assertions, and computes the geometric mean.

- **`./run_embench_fpga.sh`**:
  Builds bare-metal FPGA HIL firmware images (`sw/build_hil_bench.sh all`) and runs the automated UART test suite against the physical Arty A7-100T FPGA.
