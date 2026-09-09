#!/usr/bin/env python3
"""
run_hil_bench.py — Host-side capture and analysis for Kavacha FPGA HIL benchmarks.

Connects to the Arty A7-100T over USB-UART, captures benchmark output,
parses cycle counts, and appends results to results/hil_report.md.

Usage:
    python3 sw/run_hil_bench.py [OPTIONS]

Options:
    --port    /dev/ttyUSB1      Serial port (default: auto-detect)
    --baud    115200            Baud rate (default: 115200)
    --bench   coremark          Benchmark name to run (default: coremark)
                                Use 'all' to run all benchmarks sequentially.
    --freq    100               FPGA clock frequency in MHz (default: 100)
    --timeout 60                Seconds to wait for benchmark output (default: 60)
    --out     results/          Directory to write hil_report.md (default: bench/results)
    --mem-dir sw/hil_build/     Directory containing .mem firmware images

Workflow:
    1. Optionally flash the firmware using openFPGALoader (if --flash is passed).
    2. Open the serial port and wait for benchmark output.
    3. Parse CYCLES:<n>, ITERS:<n>, BENCH:<name>, SCALE:<n>, RESULT:<PASS|FAIL>.
    4. Calculate CoreMark/MHz and append to the results report.
"""

import argparse
import csv
import datetime
import os
import re
import subprocess
import sys
import time

# ---- Try to import pyserial ------------------------------------------------
try:
    import serial
    import serial.tools.list_ports
    HAS_SERIAL = True
except ImportError:
    HAS_SERIAL = False

# ---- Benchmark list (same order as Makefile) --------------------------------
ALL_EMBENCH = [
    "aha-mont64", "crc32", "edn", "huffbench", "matmult-int",
    "nettle-aes", "nettle-sha256", "nsichneu", "picojpeg", "qrduino",
    "sglib-combined", "slre", "tarfind", "ud", "wikisort",
]

SCALE_MAP = {
    "picojpeg": 10, "nsichneu": 10, "qrduino": 10, "wikisort": 10
}

# ---- Serial port auto-detection --------------------------------------------
def auto_detect_port():
    """Try to find the Arty A7's FTDI USB-UART bridge."""
    if not HAS_SERIAL:
        return None
    ports = list(serial.tools.list_ports.comports())
    # FTDI FT2232 as used on Arty A7 appears as ttyUSB1 (second interface)
    candidates = [p.device for p in ports if "ttyUSB" in p.device or "ttyACM" in p.device]
    if candidates:
        # Arty A7 FT2232 UART is the second channel (ttyUSB1 if only one board)
        candidates.sort()
        return candidates[-1]   # pick highest-numbered (usually the UART channel)
    return None

# ---- Flash firmware to FPGA ------------------------------------------------
def flash_firmware(bit_path, fpga="arty_a7_100t"):
    """Use openFPGALoader to program the bitstream."""
    cmd = ["openFPGALoader", "-b", fpga, bit_path]
    print(f"[FLASH] {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=False, text=True)
    if result.returncode != 0:
        print("ERROR: openFPGALoader failed. Make sure the board is connected and powered.")
        sys.exit(1)
    print("[FLASH] Programming complete. Waiting for reset...")
    time.sleep(2)   # let the core come out of reset

# ---- Capture and parse serial output ----------------------------------------
def capture_benchmark(ser, timeout, bench_name):
    """
    Read lines from the serial port until EXIT:<code> or timeout.
    Returns a dict with parsed fields.
    """
    result = {
        "bench": bench_name,
        "cycles": None,
        "iters": None,
        "scale": None,
        "status": "TIMEOUT",
        "raw": [],
    }

    deadline = time.monotonic() + timeout
    buf = b""

    print(f"[HIL] Waiting for output from '{bench_name}' (timeout={timeout}s)...")

    while time.monotonic() < deadline:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            buf += chunk
            # Process complete lines
            while b"\n" in buf:
                line_bytes, buf = buf.split(b"\n", 1)
                line = line_bytes.decode("ascii", errors="replace").strip()
                if line:
                    result["raw"].append(line)
                    print(f"  UART> {line}")

                # Parse machine-readable fields
                m = re.match(r"CYCLES:(\d+)", line)
                if m:
                    result["cycles"] = int(m.group(1))

                m = re.match(r"ITERS:(\d+)", line)
                if m:
                    result["iters"] = int(m.group(1))

                m = re.match(r"SCALE:(\d+)", line)
                if m:
                    result["scale"] = int(m.group(1))

                m = re.match(r"RESULT:(PASS|FAIL)", line)
                if m:
                    result["status"] = m.group(1)

                m = re.match(r"BENCH:(.+)", line)
                if m:
                    result["bench"] = m.group(1).strip()

                # EXIT: from crt0_fpga.S signals completion
                m = re.match(r"EXIT:(\d+)", line)
                if m:
                    code = int(m.group(1))
                    if result["status"] == "TIMEOUT":
                        result["status"] = "PASS" if code == 0 else "FAIL"
                    return result

    print(f"[HIL] TIMEOUT waiting for '{bench_name}'")
    return result

# ---- Flash a specific .mem using updatemem + reprogram ---------------------
def flash_mem(mem_path, bit_path, build_dir, fpga="arty_a7_100t"):
    """
    Copy the benchmark firmware into firmware.mem, re-run Vivado synthesis
    to bake it into the bitstream, then flash.
    updatemem cannot work with inferred BRAM ($readmemh), so full re-synthesis
    is required for each benchmark.  (~5 min per benchmark)
    """
    import shutil
    tcl_script = os.path.abspath(os.path.join(os.path.dirname(bit_path), "../" + os.path.basename(bit_path).replace(".bit", ".tcl")))
    # tcl_script is fpga/arty_a7/kavacha_arty_a7.tcl → go up two dirs to reach repo root, then sw/firmware.mem
    repo_root  = os.path.abspath(os.path.join(os.path.dirname(tcl_script), "../.."))
    fw_mem     = os.path.join(repo_root, "sw", "firmware.mem")

    # Locate vivado — check PATH first, then common install locations
    import shutil as _shutil
    vivado_bin = _shutil.which("vivado")
    if not vivado_bin:
        for candidate in [
            "/home/yash/Vivado/Vivado/2023.2/bin/vivado",
            "/tools/Xilinx/Vivado/2023.2/bin/vivado",
            "/opt/Xilinx/Vivado/2023.2/bin/vivado",
        ]:
            if os.path.isfile(candidate):
                vivado_bin = candidate
                break
    if not vivado_bin:
        print("ERROR: Cannot find Vivado. Add it to PATH or install it.")
        return

    print(f"[FLASH] Copying firmware and running Vivado synthesis (~5 min)...")
    shutil.copy(mem_path, fw_mem)

    r = subprocess.run(
        [vivado_bin, "-mode", "batch", "-source", tcl_script],
        text=True, cwd=os.path.dirname(fw_mem)
    )
    if r.returncode != 0:
        print(f"ERROR: Vivado synthesis failed (return code {r.returncode}).")
        return

    flash_firmware(bit_path, fpga)


# ---- Compute scores --------------------------------------------------------
def compute_scores(result, freq_mhz):
    scores = {}
    if result["cycles"] and result["cycles"] > 0:
        if result["bench"] == "coremark" and result["iters"]:
            cycles_per_iter = result["cycles"] / result["iters"]
            scores["cycles_per_iter"] = cycles_per_iter
            scores["coremark_per_mhz"] = 1_000_000 / cycles_per_iter
            scores["coremark_abs"] = scores["coremark_per_mhz"] * freq_mhz / 1_000_000
        elif result["bench"] == "dhrystone" and result["iters"]:
            # Real Dhrystones/sec/MHz = (iters * 1_000_000) / cycles
            scores["dhrystones_per_mhz"] = (result["iters"] * 1_000_000) / result["cycles"]
            scores["dhrystones_per_sec"] = scores["dhrystones_per_mhz"] * freq_mhz
            scores["dmips_per_mhz"] = scores["dhrystones_per_mhz"] / 1757.0
            scores["dmips"] = scores["dhrystones_per_sec"] / 1757.0
        else:
            scores["cycles"] = result["cycles"]
            scale = result.get("scale") or 100
            scores["cycles_per_iter"] = result["cycles"] / scale
    return scores

# ---- Generate markdown report ----------------------------------------------
def generate_report(all_results, freq_mhz, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    report_path = os.path.join(out_dir, "hil_report.md")
    csv_path    = os.path.join(out_dir, "hil_report.csv")

    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    existing_content = ""
    if os.path.exists(report_path):
        with open(report_path, "r") as f:
            existing_content = f.read()

    md_mode = "a" if os.path.exists(report_path) else "w"
    with open(report_path, md_mode) as f:
        if md_mode == "w":
            f.write(f"# Kavacha HIL Benchmark Report — Arty A7-100T\n\n")
            f.write(f"Generated: {now}  \n")
            f.write(f"Clock: **{freq_mhz} MHz**  \n")
            f.write(f"Method: Hardware-in-the-Loop (physical FPGA, UART capture)  \n\n")
            f.write("---\n\n")

        # CoreMark
        cm = next((r for r in all_results if r["bench"] == "coremark"), None)
        if cm:
            if "## CoreMark" not in existing_content:
                f.write("## CoreMark\n\n")
            scores = compute_scores(cm, freq_mhz)
            if "## CoreMark" not in existing_content:
                f.write(f"| Metric | Value |\n|--------|-------|\n")
            f.write(f"| Status | {cm['status']} |\n")
            if "cycles_per_iter" in scores:
                f.write(f"| Total Cycles | {cm['cycles']:,} |\n")
                f.write(f"| Iterations | {cm['iters']} |\n")
                f.write(f"| Cycles / Iteration | {scores['cycles_per_iter']:,.1f} |\n")
                f.write(f"| CoreMark/MHz | **{scores['coremark_per_mhz']:.2f}** |\n")
                f.write(f"| CoreMark (@ {freq_mhz} MHz) | {scores['coremark_per_mhz'] * freq_mhz / 1e6:.2f} |\n")
            f.write("\n---\n\n")

        # Dhrystone
        dhry = next((r for r in all_results if r["bench"] == "dhrystone"), None)
        if dhry:
            if "## Dhrystone" not in existing_content:
                f.write("## Dhrystone\n\n")
            scores = compute_scores(dhry, freq_mhz)
            if "## Dhrystone" not in existing_content:
                f.write(f"| Metric | Value |\n|--------|-------|\n")
            f.write(f"| Status | {dhry['status']} |\n")
            if "dmips_per_mhz" in scores:
                f.write(f"| Total Cycles | {dhry['cycles']:,} |\n")
                f.write(f"| Iterations | {dhry['iters']} |\n")
                f.write(f"| Dhrystones/sec/MHz | {scores['dhrystones_per_mhz']:,.1f} |\n")
                f.write(f"| DMIPS/MHz | **{scores['dmips_per_mhz']:.3f}** |\n")
            f.write("\n---\n\n")

        # EMBench table
        embench_results = [r for r in all_results if r["bench"] not in ("coremark", "dhrystone")]
        if embench_results:
            if "## EMBench-IoT" not in existing_content:
                f.write("## EMBench-IoT\n\n")
                f.write("| Benchmark | Scale | Cycles | Cycles/Iter | Status |\n")
                f.write("|-----------|-------|--------|-------------|--------|\n")
            for r in embench_results:
                scale = r.get("scale") or SCALE_MAP.get(r["bench"], 100)
                cyc_per = f"{r['cycles'] / scale:,.1f}" if r["cycles"] else "—"
                cyc = f"{r['cycles']:,}" if r["cycles"] else "—"
                f.write(f"| {r['bench']:<22} | {scale:>5} | {cyc:>14} | {cyc_per:>11} | {r['status']} |\n")
            # f.write("\n") # Removed so append looks cleaner

    # CSV
    csv_mode = "a" if os.path.exists(csv_path) else "w"
    with open(csv_path, csv_mode, newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["bench","cycles","iters","scale","status","cycles_per_iter"])
        if csv_mode == "w":
            writer.writeheader()
        for r in all_results:
            scale = r.get("scale") or SCALE_MAP.get(r["bench"], 100)
            cpi = r["cycles"] / scale if r["cycles"] else None
            writer.writerow({
                "bench": r["bench"],
                "cycles": r["cycles"] or "",
                "iters": r["iters"] or "",
                "scale": scale,
                "status": r["status"],
                "cycles_per_iter": f"{cpi:.1f}" if cpi else "",
            })

    print(f"\n[REPORT] Written: {report_path}")
    print(f"[REPORT] CSV:     {csv_path}")

# ---- Main ------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Kavacha FPGA HIL benchmark runner")
    parser.add_argument("--port",    default=None,        help="Serial port (e.g. /dev/ttyUSB1)")
    parser.add_argument("--baud",    type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--bench",   default="coremark",  help="Benchmark: coremark | <embench-name> | all")
    parser.add_argument("--freq",    type=float, default=100.0, help="FPGA clock in MHz (default: 100)")
    parser.add_argument("--timeout", type=int, default=600, help="Per-benchmark timeout in seconds (default: 600)")
    parser.add_argument("--out",     default=None,        help="Output directory for report (default: bench/results)")
    parser.add_argument("--mem-dir", default=None,        help="Directory with .mem files (default: sw/hil_build)")
    parser.add_argument("--bit",     default=None,        help="Path to .bit file for --flash")
    parser.add_argument("--flash",   action="store_true", help="Flash bitstream before running")
    parser.add_argument("--no-flash",action="store_true", help="Skip flashing (board already programmed)")
    args = parser.parse_args()

    # Resolve paths relative to script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir   = os.path.dirname(script_dir)
    bench_dir  = os.path.join(root_dir, "bench")

    mem_dir = args.mem_dir or os.path.join(script_dir, "hil_build")
    out_dir = args.out     or os.path.join(bench_dir, "results")

    default_bit = os.path.join(root_dir, "fpga", "arty_a7", "build", "kavacha_arty_a7.bit")
    bit_path = args.bit or default_bit

    # Determine which benchmarks to run
    if args.bench == "all":
        bench_list = ["coremark"] + ALL_EMBENCH
    elif args.bench == "embench":
        bench_list = ALL_EMBENCH          # skip coremark, run all EMBench
    else:
        bench_list = [args.bench]

    if not HAS_SERIAL:
        print("ERROR: pyserial is not installed.")
        print("       Install with:  pip install pyserial")
        sys.exit(1)

    # Auto-detect serial port
    port = args.port or auto_detect_port()
    if not port:
        print("ERROR: Could not auto-detect serial port. Specify with --port /dev/ttyUSB1")
        sys.exit(1)
    print(f"[HIL] Serial port: {port} @ {args.baud} baud")

    all_results = []

    for bench_name in bench_list:
        mem_file = os.path.join(mem_dir, f"{bench_name}.mem")
        if not os.path.exists(mem_file):
            print(f"[HIL] SKIP: {bench_name} — {mem_file} not found (run build_hil_bench.sh first)")
            continue

        # Flash the firmware for this benchmark
        if not args.no_flash:
            tcl_script = os.path.abspath(os.path.join(os.path.dirname(bit_path), "../" + os.path.basename(bit_path).replace(".bit", ".tcl")))
            if os.path.exists(tcl_script):
                build_dir = os.path.dirname(bit_path)
                flash_mem(mem_file, bit_path, build_dir)
            else:
                print(f"WARNING: Vivado TCL script not found at {tcl_script}")
                print("         Skipping flash — ensure the board is already programmed.")
                print("         Or specify correct bitstream path using --bit")
        else:
            print(f"[HIL] --no-flash: skipping programming for {bench_name}")

        # Open serial port and capture output
        try:
            with serial.Serial(port, args.baud, timeout=1) as ser:
                ser.reset_input_buffer()

                # The firmware prints "READY\r\n" at startup and waits for
                # any character before running the benchmark.  This prevents
                # the ~170ms CoreMark run from completing before we start listening.
                print(f"[HIL] Waiting for READY from firmware (press board reset if needed)...")
                deadline = time.monotonic() + 10  # 10-second window
                got_ready = False
                buf = b""
                while time.monotonic() < deadline:
                    chunk = ser.read(ser.in_waiting or 1)
                    if chunk:
                        buf += chunk
                        if b"READY" in buf:
                            got_ready = True
                            break

                if not got_ready:
                    print("[HIL] WARNING: Did not see READY banner — sending trigger anyway.")
                    print("              (If this is the first run after flash, press the board reset button.)")

                # Send trigger byte — firmware unblocks on any RX char
                ser.write(b"\r")
                ser.flush()
                print(f"[HIL] Trigger sent. Running benchmark...")

                result = capture_benchmark(ser, args.timeout, bench_name)
                all_results.append(result)

        except serial.SerialException as e:
            print(f"ERROR: Could not open {port}: {e}")
            sys.exit(1)

        # Print summary for this benchmark
        scores = compute_scores(result, args.freq)
        print(f"\n  [{bench_name}] status={result['status']}  cycles={result['cycles']}")
        if "coremark_per_mhz" in scores:
            print(f"  CoreMark/MHz = {scores['coremark_per_mhz']:.2f}  (@ {args.freq:.0f} MHz)")
        elif "dmips_per_mhz" in scores:
            print(f"  Dhrystones/sec = {scores['dhrystones_per_sec']:.0f}")
            print(f"  DMIPS = {scores['dmips']:.2f}")
            print(f"  DMIPS/MHz = {scores['dmips_per_mhz']:.3f}  (@ {args.freq:.0f} MHz)")
        print()

    # Generate report
    if all_results:
        generate_report(all_results, args.freq, out_dir)
    else:
        print("No benchmark results collected.")


if __name__ == "__main__":
    main()
