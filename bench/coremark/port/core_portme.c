/* ============================================================================
 * core_portme.c — CoreMark port implementation for Kavacha bare-metal.
 *
 * Implements the 5 required portability functions:
 *   portable_init()    — record cycle baseline
 *   portable_fini()    — print results, write tohost
 *   start_time()       — latch mcycle start
 *   stop_time()        — latch mcycle stop
 *   get_time()         — return elapsed ticks
 *   time_in_secs()     — convert ticks → secs (returns raw cycles since
 *                        CLOCKS_PER_SEC == 1; CoreMark score = iters/cycles)
 * ============================================================================ */

#include "coremark.h"
#include "../../common/kavacha_io.h"

/* Global timing state */
CORETIMETYPE start_time_val;
CORETIMETYPE stop_time_val;

/* Required by SEED_METHOD = SEED_VOLATILE in core_portme.h */
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* ---- CoreMark timing API ------------------------------------------------- */

void start_time(void)
{
    start_time_val = read_mcycle64();
}

void stop_time(void)
{
    stop_time_val = read_mcycle64();
}

CORETIMETYPE get_time(void)
{
    return stop_time_val - start_time_val;
}

secs_ret time_in_secs(CORETIMETYPE ticks)
{
    /* Return raw cycle count as "seconds" (CLOCKS_PER_SEC = 1).
     * CoreMark will compute:  score = ITERATIONS / time_in_secs(elapsed)
     * which gives  ITERATIONS / cycles = iters-per-cycle.
     * Multiply by your target clock frequency to get CoreMark/MHz. */
    return (secs_ret)ticks;
}

/* ---- Portable init / fini ------------------------------------------------ */

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    p->portable_id = 0x4B415641u; /* 'KAVA' */
}

void portable_fini(core_portable *p)
{
    (void)p;
    /* CoreMark's core_main() calls portable_fini() after printing its results
     * via ee_printf.  We just need to ensure a clean exit. The benchmark main
     * (below) writes tohost=1 after core_main() returns. */
}

/* =========================================================================
 * main() — CoreMark entry point.
 *
 * CoreMark's core_main() returns 0 on data-check PASS, non-zero on FAIL.
 * We map this to:
 *   tohost = 1  → PASS
 *   tohost = 2  → FAIL (data integrity check failed)
 * ========================================================================= */
extern int core_main(void);

#undef main
int main(void)
{
    int rc = core_main();   /* runs benchmark, prints results via ee_printf */

    /* Report firmware cycle side-channel for CoreMark so harness prints bench_cycles */
    report_cycles(get_time());
    write_tohost(rc == 0 ? 1u : 2u);
    return rc;
}
