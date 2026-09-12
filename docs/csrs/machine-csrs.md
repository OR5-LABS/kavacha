# Machine Mode CSRs

Kavacha implements the RISC-V Machine-Mode Control and Status Registers (CSRs) required for system initialization, interrupt gating, trap handling, and performance profiling (`kavacha_csr.sv`).

---

## 1. Machine Information Registers

These read-only registers identify the vendor, architecture, and hardware thread ID.

| CSR Name | Address | Access | Value | Description |
|----------|:-------:|:------:|:-----:|-------------|
| `mvendorid` | `0xF11` | RO | `32'h00000000` | **Vendor ID:** `0` indicates an open-source / non-commercial core. |
| `marchid` | `0xF12` | RO | `32'h41535452` | **Architecture ID:** ASCII "ASTR" — identifies the AstraV / Kavacha family. |
| `mhartid` | `0xF14` | RO | `32'h00000000` | **Hardware Thread ID:** `0` (Kavacha is a single-hart processor core). |

!!! note
    `mimpid` (0xF13) is NOT implemented. Reads return `0`.

---

## 2. Machine Status Register (`mstatus`, CSR `0x300`)

The `mstatus` register tracks global interrupt state and privilege transitions:

```
mstatus Register Layout (0x300):
 31    18 17   13 12 11 8 7   4 3   0
| Res  | MPRV | Res | MPP | MPIE | Res | MIE | Res |
```

| Bit Field | Name | Access | Reset | Functional Description |
|:---------:|:----:|:------:|:-----:|------------------------|
| **3** | `MIE` | RW | `0` | **Machine Interrupt Enable:** `1` = Global M-mode interrupts enabled. |
| **7** | `MPIE` | RW | `0` | **Machine Previous Interrupt Enable:** Stores `MIE` state prior to entering a trap. |
| **12:11** | `MPP` | RW | `2'b11` | **Machine Previous Privilege:** Stores privilege level prior to trap (`2'b11` = M, `2'b00` = U). |
| **17** | `MPRV` | RW | `0` | **Modify Privilege (SECURE only):** When set, data memory accesses use `MPP` privilege instead of current privilege. Cleared by `MRET` to non-M mode. |

---

## 3. Machine ISA Register (`misa`, CSR `0x301`)

Reports the base architecture capabilities. This register is **read-only** (writes are silently ignored).

```
misa Register Layout (0x301):
 31 30 29                    21 20  13 12  9  8   3  2   0
| MXL |       Reserved        | U | Res | M | Res | I | C | Res |
```

* **`MXL[31:30]`:** `2'b01` (32-bit native XLEN).
* **Extensions:** `I` (bit 8), `M` (bit 12), `C` (bit 2).
* **`SECURE=1`:** `U` bit 20 = 1 (User mode enabled).
* **Computed value:** `MISA_VAL = (01 << 30) | (1 << 8) | (1 << 12) | (1 << 2)` = `32'h40001104`
* **With SECURE:** `32'h40001104 | (1 << 20)` = `32'h40101104`

---

## 4. Machine Interrupt & Trap Control Registers

### `mie` (Interrupt Enable, CSR `0x304`) & `mip` (Interrupt Pending, CSR `0x344`)

```
mie / mip Bit Layout (0x304 / 0x344):
 31          12 11   8 7   4 3   0
|  Reserved    | MEIE | Res | MTIE | Res | MSIE | Res |
```

| Bit | Field | In `mie` | In `mip` | Source |
|:---:|:-----:|:--------:|:--------:|--------|
| **3** | `MSIE` / `MSIP` | RW (enable) | RO (pending) | CLINT `msip` register |
| **7** | `MTIE` / `MTIP` | RW (enable) | RO (pending) | CLINT `mtime >= mtimecmp` |
| **11** | `MEIE` / `MEIP` | RW (enable) | RO (pending) | External interrupt line (`irq_ext`) |

**Interrupt Priority (hardwired):** External (11) > Timer (7) > Software (3).

`mip` is **read-only** — its bits are driven directly by the pending interrupt lines:
```verilog
wire [31:0] mip = (irq_ext << 11) | (irq_timer << 7) | (irq_soft << 3);
```

An interrupt is taken when `mstatus.MIE == 1` AND any `(mip[i] & mie[i])` is true.

### `mtvec` (Trap Vector Base Address, CSR `0x305`)

```
mtvec Register Layout (0x305):
 31                                         2 1    0
|                BASE[31:2]                  | MODE |
```

* **`BASE[31:2]`:** 4-byte aligned base address of the Machine trap handler.
* **`MODE[1:0]`:**
  * `2'b00` (**Direct Mode**): All traps vector to `BASE`.
  * `2'b01` (**Vectored Mode**): Exceptions vector to `BASE`; interrupt $i$ vectors to `BASE + (i × 4)`.

---

## 5. Machine Trap Save & State Registers

| CSR Name | Address | Access | Reset | Description |
|----------|:-------:|:------:|:-----:|-------------|
| `mscratch` | `0x340` | RW | `0` | **Scratch Register:** For trap handlers to swap context/stack pointers. |
| `mepc` | `0x341` | RW | `0` | **Exception PC:** Captures `pc` on trap entry. Restored by `MRET`. |
| `mcause` | `0x342` | RW | `0` | **Trap Cause:** Bit 31 = `1` for interrupts, `0` for exceptions. Bits 3:0 hold cause code. |
| `mtval` | `0x343` | RW | `0` | **Trap Value:** Faulting address (access faults) or instruction word (illegal instruction). |

---

## 6. Performance Counters

| CSR Name | Address | Access | Reset | Counter Behavior |
|----------|:-------:|:------:|:-----:|------------------|
| `mcycle` | `0xB00` | RW | `0` | Lower 32 bits. Increments **unconditionally** on every `clk` rising edge. |
| `mcycleh` | `0xB80` | RW | `0` | Upper 32 bits of the 64-bit cycle counter. |
| `minstret` | `0xB02` | RW | `0` | Lower 32 bits. Increments on every retired instruction (`commit`). |

### User-Mode Read-Only Aliases

These CSRs provide **read-only** aliases to the counters, accessible from User mode:

| CSR Name | Address | Alias Of | Description |
|----------|:-------:|:--------:|-------------|
| `cycle` | `0xC00` | `mcycle` | User-mode read of lower 32-bit cycle count |
| `cycleh` | `0xC80` | `mcycleh` | User-mode read of upper 32-bit cycle count |
| `instret` | `0xC02` | `minstret` | User-mode read of lower 32-bit retired instruction count |
