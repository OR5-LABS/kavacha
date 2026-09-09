// =============================================================================
// main.cpp — Verilator C++ harness for Kavacha benchmark suite.
//
// Usage:
//   ./sim/Vbench_top --hex <path/to/bench.hex> --name <benchmark_name>
//                    [--max-cycles N] [--trace]
//
// Loads the flat 32-bit-per-line hex image directly into the Verilator
// model's imem[] array (bench_top__DOT__imem), resets the core, then runs
// the clock loop until:
//   • tohost == 1           → PASS
//   • tohost >= 2           → FAIL (code = tohost value)
//   • cycles > max_cycles   → TIMEOUT
//
// tohost side-channel protocol (used by EMBench bench_main.c):
//   write 0xC0000000|(hi24)  → upper 30 bits of 64-bit cycle count
//   write 0x80000000|(lo30)  → lower 30 bits (printed together on PASS)
//   write 1                  → PASS / done
//   write >= 2               → FAIL
// =============================================================================

#include "Vbench_top.h"
#include "Vbench_top___024root.h"
#include "verilated.h"

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cinttypes>
#include <vector>
#include <string>

// ---------------------------------------------------------------------------
static void load_hex(Vbench_top* top, const char* path)
{
    FILE* f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "[BENCH] ERROR: cannot open hex file: %s\n", path);
        exit(1);
    }

    char line[32];
    uint32_t idx = 0;
    const uint32_t IMEM_WORDS = 16384; // must match bench_top parameter

    while (fgets(line, sizeof(line), f)) {
        // Skip blank lines and comments (@address directives from objcopy)
        if (line[0] == '\n' || line[0] == '\r' || line[0] == '/')
            continue;
        if (line[0] == '@') {
            // $readmemh address directive: @<hex_addr>
            unsigned long addr = strtoul(line + 1, nullptr, 16);
            idx = (uint32_t)addr;
            continue;
        }
        if (idx >= IMEM_WORDS) {
            fprintf(stderr, "[BENCH] WARNING: hex file exceeds IMEM_WORDS=%u, truncating\n",
                    IMEM_WORDS);
            break;
        }
        char* end;
        uint32_t word = (uint32_t)strtoul(line, &end, 16);
        if (end == line) continue; // empty / non-hex line
        top->rootp->bench_top__DOT__imem[idx++] = word;
    }
    fclose(f);
    fprintf(stderr, "[BENCH] Loaded %u words from %s\n", idx, path);
}

// ---------------------------------------------------------------------------
static void zero_dram(Vbench_top* top)
{
    const uint32_t DRAM_WORDS = 16384;
    for (uint32_t i = 0; i < DRAM_WORDS; i++)
        top->rootp->bench_top__DOT__dram[i] = 0;
}

// ---------------------------------------------------------------------------
int main(int argc, char* argv[])
{
    // ---- parse args -------------------------------------------------------
    const char* hex_path   = nullptr;
    const char* bench_name = "unknown";
    uint64_t    max_cycles = 200000000ULL; // 200 M — covers CoreMark × 1000
    uint64_t    iterations = 1000;
    bool        do_trace   = false;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--hex")  && i+1 < argc) { hex_path   = argv[++i]; }
        else if (!strcmp(argv[i], "--name") && i+1 < argc) { bench_name = argv[++i]; }
        else if (!strcmp(argv[i], "--max-cycles") && i+1 < argc) {
            max_cycles = (uint64_t)strtoull(argv[++i], nullptr, 10);
        }
        else if (!strcmp(argv[i], "--iterations") && i+1 < argc) {
            iterations = (uint64_t)strtoull(argv[++i], nullptr, 10);
        }
        else if (!strcmp(argv[i], "--trace")) { do_trace = true; }
    }

    if (!hex_path) {
        fprintf(stderr, "Usage: %s --hex <file.hex> --name <name> [--max-cycles N] [--iterations N] [--trace]\n",
                argv[0]);
        return 1;
    }

    // ---- Verilator init ---------------------------------------------------
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);

    Vbench_top* top = new Vbench_top(ctx);

#if VM_TRACE
    VerilatedVcdC* tfp = nullptr;
    if (do_trace) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        std::string vcd = std::string(bench_name) + ".vcd";
        tfp->open(vcd.c_str());
        fprintf(stderr, "[BENCH] Tracing to %s\n", vcd.c_str());
    }
#endif

    // ---- initialise memories BEFORE reset ---------------------------------
    // NOP-fill IMEM, then load the benchmark image
    for (uint32_t i = 0; i < 16384; i++)
        top->rootp->bench_top__DOT__imem[i] = 0x00000013u; // ADDI x0,x0,0
    zero_dram(top);
    load_hex(top, hex_path);

    // ---- reset sequence (8 half-cycles = 4 full clocks) ------------------
    top->tck = 0; top->tms = 0; top->tdi = 0;
    top->rst = 1;
    top->clk = 0;
    for (int h = 0; h < 8; h++) {
        top->clk ^= 1;
        top->eval();
#if VM_TRACE
        if (tfp) tfp->dump(ctx->time());
#endif
        ctx->timeInc(1);
    }
    top->rst = 0;

    // ---- simulation loop --------------------------------------------------
    uint64_t    sim_cycles   = 0;
    uint64_t    bench_cycles = 0;   // cycle count reported by firmware
    uint64_t    cy_hi        = 0;   // upper 30 bits (side-channel)
    uint64_t    cy_lo        = 0;   // lower 30 bits (side-channel)
    bool        got_hi       = false;
    bool        got_lo       = false;
    int         exit_code    = 2;   // default: TIMEOUT

    while (!ctx->gotFinish() && sim_cycles < max_cycles) {
        top->clk ^= 1;
        top->eval();
#if VM_TRACE
        if (tfp) tfp->dump(ctx->time());
#endif
        ctx->timeInc(1);

        if (top->clk) {   // rising edge
            sim_cycles++;

            if (top->tohost_we) {
                uint32_t val = top->tohost;

                // Side-channel: upper 30 bits of firmware cycle count
                if ((val & 0xC0000000u) == 0xC0000000u) {
                    cy_hi   = (uint64_t)(val & 0x3FFFFFFFu);
                    got_hi  = true;
                }
                // Side-channel: lower 30 bits
                else if ((val & 0xC0000000u) == 0x80000000u) {
                    cy_lo   = (uint64_t)(val & 0x3FFFFFFFu);
                    got_lo  = true;
                }
                // Character output from _write (0x5C0000xx)
                else if ((val & 0xFF000000u) == 0x5C000000u) {
                    putchar((char)(val & 0xFF));
                    fflush(stdout);
                }
                // PASS (1 = standard pass, 0 = clean C exit(0))
                else if (val == 1u || val == 0u) {
                    exit_code = 0;
                    if (got_hi && got_lo)
                        bench_cycles = (cy_hi << 30) | cy_lo;
                    break;
                }
                // FAIL
                else {
                    fprintf(stderr, "[BENCH] FAIL: tohost=0x%08X at cycle %" PRIu64 "\n",
                            val, sim_cycles);
                    exit_code = (int)val;
                    break;
                }
            }
        }
    }

    // ---- report -----------------------------------------------------------
    if (sim_cycles >= max_cycles && exit_code == 2) {
        fprintf(stderr, "[BENCH] TIMEOUT after %" PRIu64 " cycles\n", max_cycles);
    }

    // Primary output line — parsed by run_bench.py
    if (exit_code == 0) {
        if (bench_cycles > 0) {
            printf("[BENCH] %-24s  sim_cycles=%-12" PRIu64
                   "  bench_cycles=%-12" PRIu64 "  PASS\n",
                   bench_name, sim_cycles, bench_cycles);
        } else {
            // CoreMark reports via ee_printf; we only have sim_cycles
            printf("[BENCH] %-24s  sim_cycles=%-12" PRIu64 "  PASS\n",
                   bench_name, sim_cycles);
        }
        if (!strcmp(bench_name, "coremark")) {
            uint64_t cycles = (bench_cycles > 0) ? bench_cycles : sim_cycles;
            if (cycles > 0 && iterations > 0) {
                double cpi = (double)cycles / iterations;
                double cm_mhz = 1000000.0 / cpi;
                printf("[BENCH] CoreMark / MHz: %.4f\n", cm_mhz);
            }
        }
    } else {
        printf("[BENCH] %-24s  sim_cycles=%-12" PRIu64 "  FAIL(code=%d)\n",
               bench_name, sim_cycles, exit_code);
    }

#if VM_TRACE
    if (tfp) { tfp->close(); delete tfp; }
#endif
    top->final();
    delete top;
    delete ctx;
    return exit_code;
}
