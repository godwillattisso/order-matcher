#!/usr/bin/env python3
#run_regression.py : run every UVM test with several random seeds and summarize the results.

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

# ---------------- where things are (given) ----------------
REPO = Path(__file__).resolve().parent.parent      # C:\dev\order-matcher
SIM_DIR = REPO / "sim" / "uvm"                       # xsim runs here (same folder as run_uvm.bat)
LOG_DIR = SIM_DIR / "logs"                           # one log per run

TESTS = [
    "random_mix_test",
    "calm_market_test",
    "frantic_market_test",
    "whale_test",
    "one_sided_test",
    "fill_level_test",
    "all_scenarios_test",
]

SOURCES = [
    r"..\..\rtl\book_side.sv",
    r"..\..\rtl\best_price.sv",
    r"..\..\rtl\match_engine.sv",
    r"..\..\tb\uvm\order_if.sv",
    r"..\..\tb\uvm\om_sva.sv",
    r"..\..\tb\uvm\om_pkg.sv",
    r"..\..\tb\uvm\tb_top.sv",
]


# ---------------- commands (given) ----------------
def compile_design():
    """Compile and elaborate once. Stops the script if either step fails."""
    commands = [
        "xvlog -sv -L uvm -i ..\\..\\tb\\uvm " + " ".join(SOURCES),
        "xelab tb_top -L uvm -relax -timescale 1ns/1ps -debug typical -s uvm_sim",
    ]
    for cmd in commands:
        print(f"[compile] {cmd.split()[0]} ...")
        result = subprocess.run(cmd, shell=True, cwd=SIM_DIR,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode != 0:
            print(result.stdout)
            sys.exit(f"Compile failed at: {cmd.split()[0]}")


def build_run_cmd(test, seed, log_path, n_orders=None, bp=None):
    """One xsim command. Each plusarg is QUOTED: cmd.exe splits unquoted arguments at '='."""
    cmd = f'xsim uvm_sim -runall -sv_seed {seed} -log "{log_path}" -testplusarg "UVM_TESTNAME={test}"'
    if n_orders is not None:
        cmd += f' -testplusarg "N_ORDERS={n_orders}"'
    if bp is not None:
        cmd += f' -testplusarg "BP={bp}"'
    return cmd


# ---------------- YOUR CODE ----------------
def parse_log(log_path):
    """Read one xsim log and pull out the numbers that decide pass/fail.

    Returns a dict:
        {"errors": int or None, "fatals": int or None,
         "orders": int, "trades": int, "mismatches": int,
         "coverage": float or None}
    None means "that line wasn't found" (e.g. the simulation crashed before the summary).

    The lines to look for (exactly as they appear in your Vivado logs):
        UVM_ERROR :    0
        UVM_FATAL :    0
        ... [SB] Compared 1000 orders and 691 trades against the C++ model: 0 mismatches
        ... [COV] Functional coverage: 100.0%
    """
    info = {"errors": None, "fatals": None, "orders": 0, "trades": 0,
            "mismatches": 0, "coverage": None}
    if not Path(log_path).exists():
        return info
    #read the log line by line and fill in `info` 
    with open(log_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("UVM_ERROR :"):
                info["errors"] = int(line.split(":")[1])

            elif line.startswith("UVM_FATAL :"):
                info["fatals"] = int(line.split(":")[1])

        #extracting scoreboard results     
            elif "[SB] Compared" in line:
                m = re.search(r"Compared (\d+) orders and (\d+) trades .*: (\d+) mismatches", line )

                if m:
                    info["orders"] = int(m.group(1))
                    info["trades"] = int(m.group(2))
                    info["mismatches"] = int(m.group(3))

            # Extract functional coverage
            elif "[COV] Functional coverage:" in line:
                m = re.search(r"Functional coverage: ([\d.]+)%", line)

                if m:
                    info["coverage"] = float(m.group(1))

                
    return info


def run_one(test, seed, n_orders=None, bp=None):
    """Run one test with one seed. Returns the parse_log() dict plus test, seed, seconds, passed."""
    log_path = LOG_DIR / f"{test}_seed{seed}.log"
    cmd = build_run_cmd(test, seed, log_path, n_orders, bp)
    start = time.time()
    subprocess.run(cmd, shell=True, cwd=SIM_DIR,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    seconds = time.time() - start

    info = parse_log(log_path)
    info["test"] = test
    info["seed"] = seed
    info["seconds"] = seconds
    # ===== TODO 2: decide PASS or FAIL =====
    # PASS only if: the summary was found and errors == 0, fatals == 0, AND at least 1 order was checked.
    # (Why the last part? A run that checked nothing must not count as a pass.)
    info["passed"] = (
        info["errors"] == 0
        and info["fatals"] == 0
        and info["orders"] > 0
        and info["mismatches"] == 0
    )
    return info


def print_table(results):
    """One row per run, then a total line."""

    print()
    print(f"{'TEST':<22}{'SEED':>5}{'RESULT':>8}{'ORDERS':>8}{'TRADES':>8}{'ERRORS':>8}{'COV %':>8}{'TIME s':>8}")
    print("-" * 75)

    for r in results:
        status = "PASS" if r["passed"] else "FAIL"
        errors = str(r["errors"]) if r["errors"] is not None else "-"
        coverage = f"{r['coverage']:.1f}" if r["coverage"] is not None else "-"

        print(
            f"{r['test']:<22}"
            f"{r['seed']:>5}"
            f"{status:>8}"
            f"{r['orders']:>8}"
            f"{r['trades']:>8}"
            f"{errors:>8}"
            f"{coverage:>8}"
            f"{r['seconds']:>8.1f}"
        )

    print("-" * 75)

    passed = sum(1 for r in results if r["passed"])
    total = len(results)
    orders = sum(r["orders"] for r in results)
    trades = sum(r["trades"] for r in results)
    best_coverage = max(
        (r["coverage"] for r in results if r["coverage"] is not None),
        default=0.0
    )

    print(
        f"{passed}/{total} runs passed | "
        f"{orders} orders, {trades} trades checked | "
        f"best coverage {best_coverage:.1f}%"
    )


def main():
    parser = argparse.ArgumentParser(description="Run the order-matcher UVM regression.")
    parser.add_argument("--tests", nargs="+", default=TESTS, help="test names (default: all)")
    parser.add_argument("--seeds", type=int, default=3, help="run seeds 1..N (default 3)")
    parser.add_argument("--orders", type=int, default=None, help="orders per run (default: each test's own)")
    parser.add_argument("--bp", type=int, default=None, help="back-pressure %% (default: each test's own)")
    parser.add_argument("--no-compile", action="store_true", help="skip compiling (reuse the last build)")
    args = parser.parse_args()

    SIM_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    if not (REPO / "model" / "ref_runner.exe").exists():
        sys.exit("model\\ref_runner.exe not found: build it first (see the Day 4 guide).")
    if not args.no_compile:
        compile_design()

    results = []
    for test in args.tests:
        for seed in range(1, args.seeds + 1):
            print(f"[run] {test} seed {seed} ...", end=" ", flush=True)
            r = run_one(test, seed, args.orders, args.bp)
            print("PASS" if r["passed"] else "FAIL")
            results.append(r)

    print_table(results)
    failed = [r for r in results if not r["passed"]]
    for r in failed:
        print(f"  see {LOG_DIR / (r['test'] + '_seed' + str(r['seed']) + '.log')}")
    
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
