# Getting Started

This page walks through building Kavacha, running its self-checking tests, and
co-simulating it against the golden ISA model.

## Prerequisites

| Tool | Purpose | Required |
|------|---------|----------|
| [Icarus Verilog](https://steveicarus.github.io/iverilog/) 12+ | RTL simulation (`iverilog`, `vvp`) | Yes |
| [Python](https://www.python.org/) 3.10+ | test-program builders, co-simulation | Yes |
| RISC-V GCC (`riscv-none-elf-gcc`) | rebuild the assembly test programs | Optional |
| [Vivado](https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vivado.html) | Arty A7 FPGA flows | Optional |

The RISC-V toolchain is optional because prebuilt test programs are included in
the repository — you can simulate everything without it.

## Getting the source

```bash
git clone <your-repo-url> kavacha
cd kavacha
```

## Building and running

Kavacha ships two equivalent build drivers: `build.sh` for Linux/macOS and
`build.ps1` for Windows PowerShell. Both accept the same actions.

=== "Linux / macOS"

    ```bash
    ./build.sh          # compile + self-checking smoke test
    ./build.sh cosim    # + co-simulate against the golden ISA model
    ./build.sh rvfi     # RVFI (formal interface) self-check
    ./build.sh debug    # JTAG / Debug-Module self-check
    ./build.sh pmp      # SECURE config: User mode + PMP test program
    ./build.sh epmp     # SECURE config: ePMP (mseccfg) rules
    ./build.sh ecc      # register-file SECDED ECC unit test
    ./build.sh axil     # AXI4-Lite adapter self-check
    ./build.sh fpga     # FPGA SoC sim (UART banner + LED blink)
    ./build.sh clean
    ```

=== "Windows (PowerShell)"

    ```powershell
    .\build.ps1          # compile + smoke
    .\build.ps1 cosim    # + golden co-simulation
    .\build.ps1 rvfi
    .\build.ps1 debug
    .\build.ps1 pmp
    .\build.ps1 epmp
    .\build.ps1 ecc
    .\build.ps1 axil
    .\build.ps1 fpga
    .\build.ps1 clean
    ```

By default the tools resolve `iverilog`/`vvp` from your `PATH`. To point at a
specific install, set the `IVERILOG` and `VVP` environment variables (the
Windows driver defaults to `C:\iverilog\bin`).

## Expected output

The default `sim` build assembles a small RV32IMC smoke program, runs it, and
checks the result:

```
[TB] PASS
```

The `cosim` action additionally replays every retired instruction against the
golden ISA model and confirms they match exactly:

```
[cosim] MATCH — 142 retires identical. RTL is ISA-correct.
```

The `rvfi`, `debug`, and `ecc` actions each print a `PASS` line on success.

## Next steps

- Read the **[Architecture](architecture/fsm.md)** to understand the execution
  model.
- Browse the **[Instruction Set](isa/rv32imc.md)** and **[SoC Integration](integration/soc-top.md)**.
- See **[Verification](verification/cocotb-verilator.md)** for how correctness is established.
