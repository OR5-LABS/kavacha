# Instruction Cycle Timing & CPI Breakdown

Kavacha is designed for **deterministic execution timing**. Because the core executes instructions through a small multi-cycle FSM without speculative branch prediction or variable pipeline stalls, instruction timing is mathematically exact and predictable.

---

## 1. Master Instruction Timing Reference Table

All cycle counts below assume a zero-wait-state memory system (`mem_stall = 0`).

| Instruction Category | Representative Opcodes | Executed FSM States | Base Cycles | Wait States ($W$) Impact |
|----------------------|------------------------|---------------------|:-----------:|--------------------------|
| **ALU Arithmetic & Logic** | `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLT` | `FETCH` → `EXEC` | **2** | $+W$ (Fetch only) |
| **Immediates & Shifts** | `ADDI`, `ANDI`, `SLL`, `SRL`, `SRA`, `SLLI` | `FETCH` → `EXEC` | **2** | $+W$ (Fetch only) |
| **Upper Immediates** | `LUI`, `AUIPC` | `FETCH` → `EXEC` | **2** | $+W$ (Fetch only) |
| **Unconditional Jumps** | `JAL`, `JALR` | `FETCH` → `EXEC` | **2** | $+W$ (Fetch only) |
| **Conditional Branches** | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` | `FETCH` → `EXEC` | **2** | $+W$ (Fetch only) |
| **Memory Stores** | `SB`, `SH`, `SW` | `FETCH` → `EXEC` | **2** | $+2W$ (Fetch + Store Write Beat) |
| **CSR Operations** | `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI` | `FETCH` → `EXEC` | **2** | $+W$ (Fetch only) |
| **Memory Loads** | `LB`, `LH`, `LW`, `LBU`, `LHU` | `FETCH` → `EXEC` → `LOAD` | **3** | $+2W$ (Fetch + Load Read Beat) |
| **Hardware Multiplication** | `MUL`, `MULH`, `MULHSU`, `MULHU` | `FETCH` → `EXEC` → `MD` | **3 to 34** | $+W$ (Fetch only) |
| **Hardware Division** | `DIV`, `DIVU`, `REM`, `REMU` | `FETCH` → `EXEC` → `MD` | **34** | $+W$ (Fetch only) |

---

## 2. Hardware Multiplication & Division Timing Waveforms

### Hardware Divide (`DIV` / `DIVU`) — 34 Cycles Total

```
CLK       :  _  / \  _  / \  _  / \ ... / \  _  / \  
FSM State : [ FETCH ][ EXEC ][  MD (32 cycles)  ][ FETCH ]
cnt_q     : ---------[ 31  ][ 30  ] ... [ 0   ]-----
md_ready  : ____________________________[ HIGH  ]___
Retire    : ____________________________[ VALID ]___
```

---

## 3. Average Cycles Per Instruction (CPI) Mathematical Model

The average CPI ($\text{CPI}_{\text{avg}}$) for a given workload depends on the instruction mix percentages ($w_i$) and memory wait states ($W$):

$$\text{CPI}_{\text{avg}} = \sum_{i} w_i \times (\text{BaseCycles}_i + \text{MemoryImpact}_i(W))$$

### Typical Benchmark Mix CPI Breakdown (Zero Wait States $W=0$)

| Instruction Class | Workload Mix Weight ($w_i$) | Base Cycles | Weighted Cycles |
|-------------------|----------------------------|:-----------:|:---------------:|
| ALU / Immediates / Logic | 45% | 2 | 0.90 |
| Memory Loads | 25% | 3 | 0.75 |
| Conditional Branches & Jumps | 18% | 2 | 0.36 |
| Memory Stores | 10% | 2 | 0.20 |
| Multiply / Divide | 2% | ~12 (average) | 0.24 |
| **Overall Average CPI** | **100%** | — | **~2.45** |

On zero-wait-state memory, Kavacha achieves an average throughput of **~2.45 CPI** (~0.41 instructions per cycle).

---

## 4. Memory Latency Sensitivity Analysis

When running over buses with memory wait states ($W > 0$):

$$\text{CPI}(W) = \text{CPI}_{\text{base}} + W \times (1 + w_{\text{load}} + w_{\text{store}})$$

For a typical workload mix ($w_{\text{load}} = 0.25$, $w_{\text{store}} = 0.10$):

$$\text{CPI}(W) \approx 2.45 + (1.35 \times W)$$

| Memory System Type | Memory Wait States ($W$) | Effective CPI | Effective IPC (Instr/Cycle) |
|--------------------|:-----------------------:|:-------------:|:---------------------------:|
| **Tightly-Coupled BRAM (Zero Wait)** | 0 | **2.45** | 0.408 |
| **Single-Wait-State SRAM** | 1 | **3.80** | 0.263 |
| **AXI4-Lite Fabric (2 Wait States)** | 2 | **5.15** | 0.194 |
| **Off-Chip Flash (4 Wait States)** | 4 | **7.85** | 0.127 |

---

## 5. Deterministic Execution & Real-Time Worst-Case Execution Time (WCET)

In safety-critical automotive, aerospace, and industrial control systems, **Worst-Case Execution Time (WCET)** predictability is mandatory:

1. **Zero Branch Misprediction Jitter:** Conditional branches (`BEQ`, `BNE`, `BLT`, `BGE`) execute in exactly **2 clock cycles**, regardless of whether the branch is taken or not-taken.
2. **Zero Cache Miss Jitter:** Without data caches or speculative prefetchers, execution timing is bounded purely by memory bus latency.
3. **Interrupt Latency Bound:** Interrupts are sampled at instruction boundaries (`STATE_EXEC` or `STATE_LOAD`). Maximum interrupt response latency is bounded by the longest non-preemptible instruction (34 cycles for division) plus 2 cycles for vector redirection.
