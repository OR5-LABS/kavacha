# Security & ePMP CSRs

When Kavacha is compiled in the **SECURE** configuration (`SECURE = 1` or `-DKAVACHA_SECURE`), the hardware instantiates the Enhanced PMP (ePMP) configuration register (`mseccfg`), 8 PMP region configuration entries (`pmpcfg0`–`pmpcfg1`), and 8 PMP region address registers (`pmpaddr0`–`pmpaddr7`).

---

## 1. Machine Security Configuration Register (`mseccfg`, CSR `0x747`)

The `mseccfg` register configures Enhanced PMP (ePMP) security rules:

```
mseccfg Register Layout (0x747):
 31                         3   2     1     0
|         Reserved           | RLB | MMWP | MML |
```

| Bit | Field Name | Access | Reset | Functional Description & Security Enforcement |
|:---:|:----------:|:------:|:-----:|-----------------------------------------------|
| **0** | `MML` | RW | `0` | **Machine Mode Lockdown:** Modifies permission interpretation for locked (`L=1`) PMP rules. Restricts Machine mode execution to explicitly marked executable regions and enables secure shared code/data regions between Machine and User modes. |
| **1** | `MMWP` | RW | `0` | **Machine Mode Whitelist Policy:** When set, any memory access originated by **Machine mode** that does not match an active PMP region is **denied**, switching M-mode default from allow-all to deny-all. |
| **2** | `RLB` | RW | `0` | **Rule Locking Bypass:** Controls whether locked PMP rules (`L=1`) can be dynamically updated by Machine mode software. |

---

## 2. PMP Configuration Registers (`pmpcfg0`–`pmpcfg1`, CSRs `0x3A0`–`0x3A1`)

PMP configurations are packed 4 per 32-bit CSR:
* `pmpcfg0` (`0x3A0`): Contains configuration entries for **Regions 0, 1, 2, 3**.
* `pmpcfg1` (`0x3A1`): Contains configuration entries for **Regions 4, 5, 6, 7**.

```
pmpcfg0 CSR Layout (0x3A0):
 31         24 23         16 15          8 7           0
|  pmp3cfg    |  pmp2cfg    |  pmp1cfg    |  pmp0cfg    |

Individual 8-bit PMP Region Entry Structure (pmpNcfg):
 7   6  5   4   3   2   1   0
| L | Res  |  A[1:0] | X | W | R |
```

### 8-Bit Entry Field Definitions

| Bit | Field Name | Description |
|:---:|:----------:|-------------|
| **0** | `R` | **Read Permission:** `1` = Read allowed, `0` = Read denied |
| **1** | `W` | **Write Permission:** `1` = Write allowed, `0` = Write denied |
| **2** | `X` | **Execute Permission:** `1` = Instruction fetch allowed, `0` = Fetch denied |
| **4:3** | `A` | **Address Matching Mode:** `2'b00` = OFF, `2'b01` = TOR, `2'b10` = NA4, `2'b11` = NAPOT |
| **7** | `L` | **Lock Bit:** `1` = Region locked and enforced on M-mode; `0` = Unlocked (U-mode only) |

---

## 3. PMP Address Registers (`pmpaddr0`–`pmpaddr7`, CSRs `0x3B0`–`0x3B7`)

The `pmpaddr0` through `pmpaddr7` CSRs store 32-bit physical addresses used for region matching:

| CSR Address | Register Name | Description |
|:-----------:|:-------------:|-------------|
| `0x3B0` | `pmpaddr0` | Region 0 Target Physical Address |
| `0x3B1` | `pmpaddr1` | Region 1 Target Physical Address |
| `0x3B2` | `pmpaddr2` | Region 2 Target Physical Address |
| `0x3B3` | `pmpaddr3` | Region 3 Target Physical Address |
| `0x3B4` | `pmpaddr4` | Region 4 Target Physical Address |
| `0x3B5` | `pmpaddr5` | Region 5 Target Physical Address |
| `0x3B6` | `pmpaddr6` | Region 6 Target Physical Address |
| `0x3B7` | `pmpaddr7` | Region 7 Target Physical Address |

### Address Modes & `pmpaddr` Interpretation
* **`TOR` Mode (`A = 2'b01`):** `pmpaddr[i]` forms the upper bound (`addr < pmpaddr[i]`). The lower bound is `pmpaddr[i-1]` (or `0x00000000` for `pmpaddr0`).
* **`NA4` Mode (`A = 2'b10`):** `pmpaddr[i]` holds the 4-byte aligned word address (`addr[31:2] == pmpaddr[i][29:0]`).
* **`NAPOT` Mode (`A = 2'b11`):** `pmpaddr[i]` encodes a power-of-two region size using trailing ones in `pmpaddr[i]`.

---

## 4. Privilege Violation & Access Protection

1. **User-Mode Access Block:** Attempting to read or write `mseccfg`, `pmpcfgN`, or `pmpaddrN` from User mode (`priv_mode == 2'b00`) immediately raises an **Illegal Instruction Exception** (`mcause = 32'h00000002`).
2. **Lock Bit Enforcement:** Once a region's `L` bit is set to `1` (and `mseccfg.RLB = 0`), subsequent writes to `pmpcfgN` or `pmpaddrN` for that region are ignored until a system reset.
