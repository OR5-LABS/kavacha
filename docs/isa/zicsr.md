# Zicsr Extension

Kavacha implements the **Zicsr** Control and Status Register (CSR) extension. The Zicsr extension provides atomic read-modify-write instructions to inspect, update, set, and clear CSR fields for trap handling, privilege control, security, and performance monitoring.

---

## 1. Zicsr Instruction Set

All Zicsr instructions use opcode `1110011` (`SYSTEM`) and execute in **2 clock cycles** (`STATE_FETCH → STATE_EXEC`).

| Instruction | Type | Funct3 | Operand Source | Atomic Operation | GPR Return (`rd`) | CSR Update |
|-------------|:----:|:------:|----------------|------------------|-------------------|------------|
| `CSRRW rd, csr, rs1` | I | `001` | Register `rs1_data` | Swap / Write | Old `CSR[csr]` | `CSR[csr] = rs1_data` |
| `CSRRS rd, csr, rs1` | I | `001` | Register `rs1_data` | Bitwise Set | Old `CSR[csr]` | `CSR[csr] = CSR[csr] \| rs1_data` |
| `CSRRC rd, csr, rs1` | I | `003` | Register `rs1_data` | Bitwise Clear | Old `CSR[csr]` | `CSR[csr] = CSR[csr] & ~rs1_data` |
| `CSRRWI rd, csr, uimm`| I | `101` | 5-bit `uimm[4:0]` | Swap / Write | Old `CSR[csr]` | `CSR[csr] = zero_extend(uimm)` |
| `CSRRSI rd, csr, uimm`| I | `110` | 5-bit `uimm[4:0]` | Bitwise Set | Old `CSR[csr]` | `CSR[csr] = CSR[csr] \| zero_extend(uimm)` |
| `CSRRCI rd, csr, uimm`| I | `111` | 5-bit `uimm[4:0]` | Bitwise Clear | Old `CSR[csr]` | `CSR[csr] = CSR[csr] & ~zero_extend(uimm)` |

### SystemVerilog Atomic CSR Operation Logic (`kavacha_csr.sv`)

```verilog
always_comb begin
  csr_wdata_int = csr_rdata;
  case (csr_op_i)
    CSR_WRITE: csr_wdata_int = operand_val;
    CSR_SET:   csr_wdata_int = csr_rdata | operand_val;
    CSR_CLEAR: csr_wdata_int = csr_rdata & ~operand_val;
    default:   csr_wdata_int = csr_rdata;
  endcase
end
```

---

## 2. Read / Write Side-Effect Suppressions

To prevent unnecessary CSR side-effects (such as clearing interrupt flags or incrementing counters), Kavacha enforces standard RISC-V read/write suppression rules in `kavacha_csr.sv`:

### Write Suppression (`rs1 == x0` or `uimm == 0`)
* For `CSRRS` and `CSRRC`: If `rs1 == 5'b00000`, no CSR write is performed. The instruction acts as a **pure atomic read**.
* For `CSRRSI` and `CSRRCI`: If `uimm == 5'b00000`, no CSR write is performed.

### Read Suppression (`rd == x0`)
* If destination register `rd == 5'b00000`, the CSR is read internally to perform bitwise modification, but no data is written to the GPR register file.

---

## 3. Complete Architectural CSR Map & Register Bitfields

```
mstatus (0x300):
 31       13 12 11 8 7   6 5 4 3   2 1 0
| Reserved  | MPP | Res | MPIE | Res | MIE |

mie / mip (0x304 / 0x344):
 31          12 11   10 9   8 7   6 5   4 3   2 1 0
|  Reserved    | MEIE | Res | SEIE | Res | MTIE | Res | MSIE |

mtvec (0x305):
 31                                         2 1    0
|                BASE[31:2]                  | MODE |
```

| Address | CSR Name | Access | Reset Value | Description / Bitfields |
|---------|----------|:------:|:-----------:|-------------------------|
| `0xF11` | `mvendorid` | RO | `32'h00000000` | Vendor ID (non-commercial / open-source) |
| `0xF12` | `marchid` | RO | `32'h00000030` | Architecture ID for Kavacha core |
| `0xF13` | `mimpid` | RO | `32'h00010000` | Implementation version (v1.0.0) |
| `0xF14` | `mhartid` | RO | `32'h00000000` | Hardware thread (hart) ID (0) |
| `0x300` | `mstatus` | RW | `32'h00000000` | Machine status (`MIE` bit 3, `MPIE` bit 7, `MPP[1:0]` bits 12:11) |
| `0x301` | `misa` | RO | `32'h40001104` | RV32IMC base capability (`SECURE=0`) or `32'h40101104` (`SECURE=1`) |
| `0x304` | `mie` | RW | `32'h00000000` | Machine interrupt enables (`MTIE` bit 7, `MSIE` bit 3, `MEIE` bit 11) |
| `0x305` | `mtvec` | RW | `32'h00000000` | Trap vector base address (`BASE[31:2]`) and mode (`MODE[1:0]`) |
| `0x340` | `mscratch`| RW | `32'h00000000` | Scratch register for Machine trap handlers |
| `0x341` | `mepc` | RW | `32'h00000000` | Exception program counter (return address on `MRET`) |
| `0x342` | `mcause` | RW | `32'h00000000` | Trap cause (Interrupt bit 31 + Exception code bits 30:0) |
| `0x343` | `mtval` | RW | `32'h00000000` | Trap value (faulting memory address or instruction word) |
| `0x344` | `mip` | RW/RO | `32'h00000000` | Machine interrupt pending status (`MTIP` bit 7, `MSIP` bit 3, `MEIP` bit 11) |
| `0xB00` | `mcycle` | RW | `32'h00000000` | Machine performance cycle counter |
| `0xB02` | `minstret`| RW | `32'h00000000` | Machine performance retired-instruction counter |
| `0x747` | `mseccfg` | RW | `32'h00000000` | Machine Security Configuration (`SECURE=1`: `MML` bit 0, `MMWP` bit 1, `RLB` bit 2) |
| `0x3A0` | `pmpcfg0` | RW | `32'h00000000` | PMP Region 0-3 configuration registers |
| `0x3B0` | `pmpaddr0`| RW | `32'h00000000` | PMP Region 0 physical address register |

---

## 4. Illegal CSR Access Exceptions

An **Illegal Instruction Exception** (`mcause = 32'h00000002`) is raised in `STATE_EXEC` if software attempts to:
1. Write to a read-only CSR (e.g. attempting `CSRRW` on `mvendorid` or `misa`).
2. Access a CSR above the current privilege level (e.g. User mode executing `CSRR` on `mstatus` or `mtvec`).
3. Access an unimplemented CSR address.

When an illegal CSR access occurs:
* `rf_we` and `csr_we` are suppressed (no architectural state changes).
* `mtval` is loaded with the faulting 32-bit instruction word.
* PC vectors to `mtvec`.
