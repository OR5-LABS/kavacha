# RV32IMC Base & Compressed Extensions

Kavacha fully implements the **RV32IMC** RISC-V Unprivileged Instruction Set Architecture. `misa` reports base `XLEN = 32` with extensions `I` (Base Integer), `M` (Hardware Multiply/Divide), and `C` (Compressed 16-bit Instructions).

---

## 1. Instruction Formats & Bit-Level Encoding

All standard 32-bit instructions belong to one of six core instruction formats (R, I, S, B, U, J). Fields are decoded in parallel by `kavacha_decode.sv`:

```
           31        25 24    20 19    15 14  12 11     7 6      0
R-Type   |   funct7   |   rs2  |   rs1  |funct3|   rd    | opcode |
I-Type   |        imm[11:0]    |   rs1  |funct3|   rd    | opcode |
S-Type   | imm[11:5]  |   rs2  |   rs1  |funct3| imm[4:0]| opcode |
B-Type   |i[12|10:5]  |   rs2  |   rs1  |funct3|i[4:1|11]| opcode |
U-Type   |                 imm[31:12]          |   rd    | opcode |
J-Type   |i[20|10:1|11|19:12]                  |   rd    | opcode |
```

### SystemVerilog Decoder Field Extraction (`kavacha_decode.sv`)

```verilog
always_comb begin
  opcode = instr_i[6:0];
  rd     = instr_i[11:7];
  funct3 = instr_i[14:12];
  rs1    = instr_i[19:15];
  rs2    = instr_i[24:20];
  funct7 = instr_i[31:25];
end
```

---

## 2. RV32I Base Integer Instruction Set

### Arithmetic, Logical & Comparison Instructions

| Instruction | Type | Opcode | Funct3 | Funct7 / Imm | Mathematical Operation | Execution Cycles |
|-------------|:----:|:------:|:------:|:------------:|------------------------|:----------------:|
| `ADD rd, rs1, rs2` | R | `0110011` | `000` | `0000000` | `R[rd] = R[rs1] + R[rs2]` | 2 |
| `SUB rd, rs1, rs2` | R | `0110011` | `000` | `0100000` | `R[rd] = R[rs1] - R[rs2]` | 2 |
| `ADDI rd, rs1, imm` | I | `0010011` | `000` | `imm[11:0]` | `R[rd] = R[rs1] + imm` | 2 |
| `SLT rd, rs1, rs2` | R | `0110011` | `010` | `0000000` | `R[rd] = (signed(R[rs1]) < signed(R[rs2])) ? 1 : 0` | 2 |
| `SLTU rd, rs1, rs2` | R | `0110011` | `011` | `0000000` | `R[rd] = (unsigned(R[rs1]) < unsigned(R[rs2])) ? 1 : 0` | 2 |
| `SLTI rd, rs1, imm` | I | `0010011` | `010` | `imm[11:0]` | `R[rd] = (signed(R[rs1]) < signed(imm)) ? 1 : 0` | 2 |
| `SLTIU rd, rs1, imm` | I | `0010011` | `011` | `imm[11:0]` | `R[rd] = (unsigned(R[rs1]) < unsigned(imm)) ? 1 : 0` | 2 |
| `AND rd, rs1, rs2` | R | `0110011` | `111` | `0000000` | `R[rd] = R[rs1] & R[rs2]` | 2 |
| `OR rd, rs1, rs2` | R | `0110011` | `110` | `0000000` | `R[rd] = R[rs1] \| R[rs2]` | 2 |
| `XOR rd, rs1, rs2` | R | `0110011` | `100` | `0000000` | `R[rd] = R[rs1] ^ R[rs2]` | 2 |
| `ANDI rd, rs1, imm` | I | `0010011` | `111` | `imm[11:0]` | `R[rd] = R[rs1] & sign_extend(imm)` | 2 |
| `ORI rd, rs1, imm` | I | `0010011` | `110` | `imm[11:0]` | `R[rd] = R[rs1] \| sign_extend(imm)` | 2 |
| `XORI rd, rs1, imm` | I | `0010011` | `100` | `imm[11:0]` | `R[rd] = R[rs1] ^ sign_extend(imm)` | 2 |

### Shift Instructions

| Instruction | Type | Opcode | Funct3 | Funct7 / Shamt | Shift Logic | Execution Cycles |
|-------------|:----:|:------:|:------:|:--------------:|-------------|:----------------:|
| `SLL rd, rs1, rs2` | R | `0110011` | `001` | `0000000` | `R[rd] = R[rs1] << R[rs2][4:0]` (Logical Left) | 2 |
| `SRL rd, rs1, rs2` | R | `0110011` | `101` | `0000000` | `R[rd] = R[rs1] >> R[rs2][4:0]` (Logical Right) | 2 |
| `SRA rd, rs1, rs2` | R | `0110011` | `101` | `0100000` | `R[rd] = signed(R[rs1]) >>> R[rs2][4:0]` (Arithmetic Right) | 2 |
| `SLLI rd, rs1, shamt`| I | `0010011` | `001` | `0000000` | `R[rd] = R[rs1] << shamt[4:0]` | 2 |
| `SRLI rd, rs1, shamt`| I | `0010011` | `101` | `0000000` | `R[rd] = R[rs1] >> shamt[4:0]` | 2 |
| `SRAI rd, rs1, shamt`| I | `0010011` | `101` | `0100000` | `R[rd] = signed(R[rs1]) >>> shamt[4:0]` | 2 |

### Upper Immediate & Control Transfer (Jumps & Branches)

| Instruction | Type | Opcode | Description / Operation | Execution Cycles |
|-------------|:----:|:------:|-------------------------|:----------------:|
| `LUI rd, imm` | U | `0110111` | Load Upper Immediate: `R[rd] = {imm[31:12], 12'b0}` | 2 |
| `AUIPC rd, imm` | U | `0010111` | Add Upper Immediate to PC: `R[rd] = PC + {imm[31:12], 12'b0}` | 2 |
| `JAL rd, offset` | J | `1101111` | Jump & Link: `R[rd] = PC + (is_rvc ? 2 : 4); PC = PC + offset` | 2 |
| `JALR rd, rs1, offset`| I | `1100111` | Jump & Link Reg: `R[rd] = PC + (is_rvc ? 2 : 4); PC = (R[rs1] + offset) & ~1` | 2 |
| `BEQ rs1, rs2, offset`| B | `1100011` | Branch Equal: `if (R[rs1] == R[rs2]) PC += offset` | 2 |
| `BNE rs1, rs2, offset`| B | `1100011` | Branch Not Equal: `if (R[rs1] != R[rs2]) PC += offset` | 2 |
| `BLT rs1, rs2, offset`| B | `1100011` | Branch Less Than: `if (signed(R[rs1]) < signed(R[rs2])) PC += offset` | 2 |
| `BGE rs1, rs2, offset`| B | `1100011` | Branch Greater/Equal: `if (signed(R[rs1]) >= signed(R[rs2])) PC += offset` | 2 |
| `BLTU rs1, rs2, offset`| B | `1100011` | Branch Less Than Unsigned: `if (unsigned(R[rs1]) < unsigned(R[rs2])) PC += offset` | 2 |
| `BGEU rs1, rs2, offset`| B | `1100011` | Branch Greater/Equal Unsigned: `if (unsigned(R[rs1]) >= unsigned(R[rs2])) PC += offset` | 2 |

---

## 3. M Extension (Hardware Multiply & Divide)

The M-extension unit (`kavacha_muldiv.sv`) provides 32-bit hardware integer multiplication, division, and remainder operations.

* **Multiply:** Uses a combinational 33×33-bit signed product (`a_ext * b_ext`). The result is available in a single clock cycle after latching operands.
* **Division:** Iterative shift-subtract algorithm over 32 steps (`bit_idx` counts 31→0) plus a sign-fixup cycle (`S_FIN`).

```verilog
// Multiply: combinational 33x33 signed product (kavacha_muldiv.sv)
wire signed [32:0] a_ext = {is_signed_a ? a_q[31] : 1'b0, a_q};
wire signed [32:0] b_ext = {is_signed_b ? b_q[31] : 1'b0, b_q};
wire signed [65:0] prod_full = a_ext * b_ext;
wire [63:0] prod = prod_full[63:0];

// Division: iterative shift-subtract (kavacha_muldiv.sv)
S_DIV: begin
  if (rem_shifted >= {1'b0, divisor_mag}) begin
    rem_q      <= rem_shifted - {1'b0, divisor_mag};
    quotient_q <= (quotient_q << 1) | 32'd1;
  end else begin
    rem_q      <= rem_shifted;
    quotient_q <= (quotient_q << 1);
  end
  if (bit_idx == 5'd0) state <= S_FIN;
  else                 bit_idx <= bit_idx - 1'b1;
end
```

| Instruction | Funct3 | Operation | Formula | Execution Cycles |
|-------------|:------:|-----------|---------|:----------------:|
| `MUL rd, rs1, rs2` | `000` | Multiply Low 32-bit | `R[rd] = (R[rs1] × R[rs2])[31:0]` | **3** |
| `MULH rd, rs1, rs2` | `001` | Multiply High Signed | `R[rd] = (signed(R[rs1]) × signed(R[rs2]))[63:32]` | **3** |
| `MULHSU rd, rs1, rs2`| `010` | Multiply High Signed×Unsigned | `R[rd] = (signed(R[rs1]) × unsigned(R[rs2]))[63:32]` | **3** |
| `MULHU rd, rs1, rs2` | `011` | Multiply High Unsigned | `R[rd] = (unsigned(R[rs1]) × unsigned(R[rs2]))[63:32]` | **3** |
| `DIV rd, rs1, rs2` | `100` | Divide Signed | `R[rd] = signed(R[rs1]) / signed(R[rs2])` | **36** |
| `DIVU rd, rs1, rs2` | `101` | Divide Unsigned | `R[rd] = unsigned(R[rs1]) / unsigned(R[rs2])` | **36** |
| `REM rd, rs1, rs2` | `110` | Remainder Signed | `R[rd] = signed(R[rs1]) % signed(R[rs2])` | **36** |
| `REMU rd, rs1, rs2` | `111` | Remainder Unsigned | `R[rd] = unsigned(R[rs1]) % unsigned(R[rs2])` | **36** |

### Standard Division Corner Cases

Kavacha strictly adheres to the RISC-V Privileged & Unprivileged ISA specifications for division by zero and signed overflow:

| Condition | Instruction | Dividend (`rs1`) | Divisor (`rs2`) | Result Written to `rd` |
|-----------|-------------|------------------|-----------------|------------------------|
| **Division by Zero** | `DIV` / `DIVU` | $x$ | `0` | `-1` (`32'hFFFFFFFF`) |
| **Division by Zero** | `REM` / `REMU` | $x$ | `0` | $x$ (Dividend `rs1_data`) |
| **Signed Overflow** | `DIV` | `-2147483648` (`0x80000000`) | `-1` (`0xFFFFFFFF`) | `-2147483648` (`0x80000000`) |
| **Signed Overflow** | `REM` | `-2147483648` (`0x80000000`) | `-1` (`0xFFFFFFFF`) | `0` (`32'h00000000`) |

---

## 4. C Extension (16-bit Compressed Instructions)

Kavacha supports RVC compressed instructions, improving software code density by 25–35%. 

### PC Alignment & Increment Rules
* **Instruction Fetch Alignment:** Instructions can be aligned to any 16-bit halfword boundary (`imem_addr[0] == 0`).
* **PC Advancement:** When `kavacha_rvc` expands a valid 16-bit RVC instruction (`is_rvc == 1`), the program counter advances by **+2 bytes** (`pc <= pc + 2`). For standard 32-bit instructions, PC advances by **+4 bytes** (`pc <= pc + 4`).
* **Branch/Jump Targets:** Target addresses for branches (`C.BEQZ`, `C.BNEZ`) and jumps (`C.J`, `C.JAL`, `C.JR`, `C.JALR`) can target any 16-bit aligned instruction.
