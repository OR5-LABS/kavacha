# Cocotb & Verilator Co-Simulation

Kavacha features a modern Python-based test harness built on **Cocotb** and **Verilator** (`tb/`). 

Rather than relying solely on traditional Verilog testbenches, this co-simulation infrastructure compiles the SystemVerilog RTL into a high-performance C++ simulator via Verilator, allowing Python test scripts (`tb/tb_soc.py`) to drive clocks, inject faults, load ELF binaries, and verify register writebacks.

---

## 1. Verification Infrastructure Architecture

```mermaid
flowchart LR
    subgraph Python_Environment [Python Verification Harness (Cocotb)]
        TEST[tb/tb_soc.py<br/>Test Suite Driver]
        GOLDEN[Golden Reference ISS<br/>Spike / PyRISCV State]
        CHECK[State Comparator & Checker]
    end
    
    subgraph C_Verilator [C++ Verilated Model (Verilator)]
        VCORE[Vkavacha_soc<br/>Verilated Executable]
    end
    
    subgraph SystemVerilog_RTL [SystemVerilog RTL]
        RTL[kavacha_soc.sv Top Module]
    end
    
    TEST -->|GPI Port Signals| VCORE
    VCORE <----> RTL
    VCORE -->|RVFI Retire Stream| CHECK
    GOLDEN -->|Expected Reg / PC| CHECK
    CHECK -->|Mismatch Detected| FAIL[Assertion Error & Log]
    CHECK -->|All Instructions Pass| PASS[Test Suite PASS]
```

---

## 2. Key Verification Components (`tb/`)

| File / Component | Language | Functional Role |
|------------------|:--------:|-----------------|
| **`tb/tb_soc.py`** | Python | Core Cocotb test suite. Drives `clk`/`rst_n`, monitors `tohost`, inspects register files, and compares execution against golden reference models. |
| **`tb/tb_soc.sv`** | SystemVerilog | Testbench wrapper around `kavacha_soc` exposing debug, UART, and RVFI verification buses. |
| **`tb/Makefile`** | GNU Makefile | Automates Verilator linting, C++ compilation, and Cocotb test execution. |
| **`build.sh`** | Bash | Master unified build script driving testbenches, ISA compliance, synthesis, and documentation. |

---

## 3. Golden Reference Co-Simulation & Self-Checking

On every instruction retirement (`rvfi_valid == 1`), `tb_soc.py` samples the RISC-V Formal Interface (RVFI) signals and compares them against the golden software model:

```python
# Cocotb Instruction Retirement Checker (tb/tb_soc.py)
@cocotb.test()
async def test_kavacha_execution(dut):
    # Initialize clock and reset core
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    
    while True:
        await RisingEdge(dut.clk)
        if dut.rvfi_valid.value == 1:
            pc = dut.rvfi_pc_rdata.value.integer
            rd = dut.rvfi_rd_addr.value.integer
            wdata = dut.rvfi_rd_wdata.value.integer
            
            # Verify against golden software model
            expected_wdata = golden_iss.step(pc)
            assert wdata == expected_wdata, f"Mismatch at PC {hex(pc)}: GPR x{rd} actual={hex(wdata)} expected={hex(expected_wdata)}"
```

---

## 4. Execution Commands (`build.sh`)

All test suites are driven through the unified master build script:

```bash
# 1. Run standard basic unit test suite via Cocotb + Verilator
./build.sh test

# 2. Run official RISC-V Architectural Compliance suite (riscv-tests)
./build.sh isa

# 3. Run 8-region PMP verification suite under SECURE=1
./build.sh pmp

# 4. Run ePMP (mseccfg) rule verification suite under SECURE=1
./build.sh epmp

# 5. Run SECDED ECC register file unit testbench
./build.sh ecc

# 6. Run complete all-inclusive verification suite
./build.sh all
```

---

## 5. Waveform Dump & Debugging

When a test fails, Cocotb automatically generates a full FST/VCD waveform trace:

```bash
# View waveform in GTKWave
gtkwave dump.fst
```
