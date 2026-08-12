# Kavacha

**Kavacha** (*"armour"*) is a compact, area-optimized **RV32IMC** processor
core. It executes one instruction at a time through a small multi-cycle finite
state machine — no pipeline, no forwarding, and no hazard logic — which keeps
the design tiny, easy to reason about, and straightforward to verify.

The core targets embedded and control-plane roles where silicon area, power,
and predictability matter more than peak throughput: microcontrollers, boot and
management engines, deeply embedded state machines, and FPGA soft cores.

---

## Highlights

- **ISA:** RV32IMC — base integer, `M` multiply/divide, and `C` compressed
  instructions, with the `Zicsr` control-and-status extension.
- **Microarchitecture:** multi-cycle, non-pipelined FSM
  (`FETCH → EXEC → {LOAD | MD} → FETCH`). Exactly one instruction is in flight,
  so there are no data or control hazards to resolve.
- **Privilege:** Machine mode always; an optional **User mode** (the `SECURE`
  configuration) adds a full M/U privilege split.
- **Memory protection:** optional **8-region PMP** with TOR / NA4 / NAPOT
  matching, R/W/X permissions, locking, and **ePMP** (`mseccfg`) semantics.
- **Traps & interrupts:** precise exceptions, `ECALL` / `EBREAK` / illegal-
  instruction handling, `MRET`, and timer / software / external interrupt lines.
- **Misaligned access:** hardware support for misaligned loads and stores
  (handled as a two-beat memory sequence).
- **Debug:** RISC-V External Debug (Debug Spec 0.13.2) — a JTAG Transport
  Module plus a Debug Module that OpenOCD and GDB drive out of the box
  (halt / resume, single-step, GPR & CSR access, system-bus memory access).
- **Reliability option:** register file with **SECDED ECC** (single-error
  correct, double-error detect) in the `SECURE` configuration.
- **Buses:** a minimal native memory interface, plus an **AXI4-Lite** wrapper
  for drop-in integration into standard SoC fabrics.
- **Verification:** self-checking tests, cycle-accurate **co-simulation against
  a golden RV32IM ISA model**, an **RVFI** (RISC-V Formal Interface) port for
  formal checking, and a Debug-Module self-check.

---

## Repository layout

```
kavacha/
├── rtl/                 core RTL
│   ├── kavacha_core.sv    multi-cycle control FSM + datapath
│   ├── kavacha_soc.sv     minimal SoC (IMEM/DRAM, tohost, Debug Module)
│   ├── kavacha_debug.sv   JTAG DTM + RISC-V Debug Module
│   ├── kavacha_axil.sv    AXI4-Lite master / slave / SoC wrapper
│   └── common/            shared, pre-verified datapath leaf cells
│                          (ALU, multiply/divide, register file, CSR file,
│                           immediate/branch units, decoder, RVC, PMP, ECC)
├── tb/                  testbenches (smoke, RVFI, debug, AXI-Lite, ECC)
├── tools/              golden ISA model + co-simulation driver
├── programs/           test-program builders
├── sw/                 assembly test programs & bring-up firmware
├── fpga/               FPGA SoC + Arty A7 / ZCU102 constraints
├── docs/               documentation site (MkDocs)
├── build.sh            Linux/macOS build & test driver
└── build.ps1           Windows (PowerShell) build & test driver
```

## Requirements

- **Icarus Verilog 12+** (`iverilog` / `vvp`) for simulation
- **Python 3.10+** for the test-program builders and co-simulation
- *(optional)* a RISC-V GCC toolchain to rebuild the assembly test programs
- *(optional)* Vivado for the Arty A7 / ZCU102 FPGA flows

## Build & test

Linux / macOS:

```bash
chmod +x build.sh   # make the build.sh file executable

./build.sh          # compile + self-checking smoke test
./build.sh cosim    # + co-simulate against the golden ISA model
./build.sh rvfi     # RVFI (formal interface) self-check
./build.sh debug    # JTAG / Debug-Module self-check
./build.sh pmp      # SECURE config: User mode + PMP test program
./build.sh ecc      # register-file SECDED ECC unit test
./build.sh clean
```

Windows (PowerShell):

```powershell
.\build.ps1          # compile + smoke
.\build.ps1 cosim    # + golden co-simulation
.\build.ps1 rvfi
.\build.ps1 debug
.\build.ps1 ecc
```

Expected output for the default build:

```
[TB] PASS
[cosim] MATCH — 142 retires identical. RTL is ISA-correct.
```

## Configurations

Kavacha ships in two build-time configurations, selected by a parameter /
define:

| Configuration | Privilege | Memory protection | Register file | Use case |
|---------------|-----------|-------------------|---------------|----------|
| **Default**   | Machine only | — | plain | smallest footprint |
| **`SECURE`**  | Machine + User | 8-region PMP + ePMP | SECDED ECC | isolation & reliability |

Enable the secure configuration with the `SECURE` RTL parameter, or at compile
time with `-DKAVACHA_SECURE`.

## Documentation

Full documentation — architecture, ISA, memory map, CSRs, security model,
debug, bus integration, FPGA bring-up, and verification — lives in [`docs/`](docs)
and builds into a browsable site with [MkDocs](https://www.mkdocs.org/):

```bash
pip install -r docs/requirements.txt
mkdocs serve      # http://127.0.0.1:8000
```

## License

Released under the [MIT License](LICENSE).
