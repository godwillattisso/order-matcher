#!/usr/bin/env python3
"""board_client.py : talk to the order matcher on the Basys3 over USB serial.

Two modes:
  check  : send N random orders, read every reply, then check the board's answers against the
           SAME C++ model the UVM scoreboard uses (hardware-in-the-loop check), plus the cycle counts.
             python scripts\\board_client.py --port COM4 check --orders 1000
  manual : type orders yourself and watch trades come back (and the 7-segment display change).
             python scripts\\board_client.py --port COM4 manual

Protocol (must match order_rx.sv and report_tx.sv):
  PC -> board : 0xA5 id side price qty          (side 0 = BUY, 1 = SELL)
  board -> PC : 'T' buy_id sell_id price qty     one per trade
                'D' id status cycles             once per order, last  (status 0 RESTED, 1 FILLED, 2 REJECTED)

Needs pyserial:   pip install pyserial
"""

import argparse
import random
import subprocess
import sys
import time
from pathlib import Path

import serial  # from the pyserial package

REPO = Path(__file__).resolve().parent.parent
MODEL = REPO / "model" / "ref_runner.exe"
OUT_DIR = REPO / "sim" / "hw"                   # orders + results files from the board run

HEADER = 0xA5
MSG_TRADE = ord("T")
MSG_DONE = ord("D")
STATUS_NAME = {0: "RESTED", 1: "FILLED", 2: "REJECTED"}


# ---------------- given helpers ----------------
def read_exact(port, n):
    """Read exactly n bytes, or raise TimeoutError (the board didn't answer in time)."""
    data = port.read(n)
    if len(data) != n:
        raise TimeoutError(f"expected {n} byte(s) from the board, got {len(data)}")
    return data


def make_orders(n, seed):
    """Same mix as the UVM random test: prices 4-11, sizes 1-8, 10% whales (20-60)."""
    rng = random.Random(seed)
    orders = []
    for i in range(n):
        side = rng.randint(0, 1)
        price = rng.randint(4, 11)
        qty = rng.randint(20, 60) if rng.random() < 0.10 else rng.randint(1, 8)
        orders.append((i % 256, side, price, qty))
    return orders


def expected_cycles(status, n_trades):
    """Engine cycles predicted by the simulation (Day 3): FILLED 2 + 2/trade, else 4 + 2/trade."""
    return 2 + 2 * n_trades if status == 1 else 4 + 2 * n_trades



def encode_order(oid, side, price, qty):
    """Encode an order into a 5-byte UART packet."""

    if not (0 <= oid <= 255):
        raise ValueError("Order ID must be between 0 and 255")

    if side not in (0, 1):
        raise ValueError("Side must be 0 (BUY) or 1 (SELL)")

    if not (0 <= price <= 15):
        raise ValueError("Price must be between 0 and 15")

    if not (1 <= qty <= 255):
        raise ValueError("Quantity must be between 1 and 255")

    return bytes([HEADER, oid, side, price, qty])




def read_reply(port):
    """Read all trades and the final done message for one order."""

    trades = []

    while True:
        kind = read_exact(port, 1)[0]

        if kind == MSG_TRADE:
            buy_id, sell_id, price, qty = read_exact(port, 4)

            trades.append((buy_id, sell_id, price, qty))

        elif kind == MSG_DONE:
            done_id, status, cycles = read_exact(port, 3)

            return trades, done_id, status, cycles

        else:
            raise ValueError(
                f"Unknown message type: 0x{kind:02X}"
            )


def compare_files(hw_path, ref_path):
    """Compare hardware results against the C++ reference model."""

    hw_lines = [
        line.strip()
        for line in Path(hw_path).read_text().splitlines()
        if line.strip()
    ]

    ref_lines = [
        line.strip()
        for line in Path(ref_path).read_text().splitlines()
        if line.strip()
    ]

    diffs = []

    for i in range(max(len(hw_lines), len(ref_lines))):

        hw_line = hw_lines[i] if i < len(hw_lines) else "<missing>"
        ref_line = ref_lines[i] if i < len(ref_lines) else "<missing>"

        if hw_line != ref_line:
            diffs.append((i + 1, hw_line, ref_line))

    return diffs


# ---------------- modes (given) ----------------
def open_port(name):
    port = serial.Serial(name, 115200, timeout=1.0)   # 8N1 is pyserial's default
    time.sleep(0.1)
    port.reset_input_buffer()                         # drop anything left from before
    return port


def run_check(port, n, seed, verbose):
    # The C++ model starts with an EMPTY book, so the board's book must be empty too.
    input("Press the centre button (btnC) on the board to clear its book, then press Enter here...")
    orders = make_orders(n, seed)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    orders_path, hw_path, ref_path = OUT_DIR / "orders.txt", OUT_DIR / "hw.txt", OUT_DIR / "expected.txt"

    hw_lines, cyc_bad, n_trades, cyc_sum = [], 0, 0, 0
    start = time.time()
    for idx, (oid, side, price, qty) in enumerate(orders):
        port.write(encode_order(oid, side, price, qty))
        trades, done_id, status, cycles = read_reply(port)
        if done_id != oid:
            raise RuntimeError(f"order {idx}: board answered for id {done_id}, expected {oid}")

        hw_lines.append(f"S {idx} {len(trades)} {status}")
        hw_lines += [f"T {idx} {b} {s} {p} {q}" for (b, s, p, q) in trades]
        n_trades += len(trades)
        cyc_sum += cycles
        if cycles != expected_cycles(status, len(trades)):
            cyc_bad += 1
            print(f"  cycle count order {idx}: board {cycles}, expected {expected_cycles(status, len(trades))}")
        if verbose and idx < 20:
            side_s = "BUY " if side == 0 else "SELL"
            print(f"  #{idx:<4} {side_s} {qty:>3} @ {price:<2} -> {STATUS_NAME.get(status, status):<8} "
                  f"{len(trades)} trade(s), {cycles} cycles")
    seconds = time.time() - start

    orders_path.write_text("".join(f"{o} {s} {p} {q}\n" for (o, s, p, q) in orders))
    hw_path.write_text("\n".join(hw_lines) + "\n")
    if not MODEL.exists():
        sys.exit(f"{MODEL} not found: build it first (see the Day 4 guide).")
    subprocess.run([str(MODEL), str(orders_path), str(ref_path)], check=True, stdout=subprocess.DEVNULL)
    diffs = compare_files(hw_path, ref_path)

    for (line, a, b) in diffs[:10]:
        print(f"  MISMATCH line {line}: board='{a}'  C++='{b}'")
    print()
    print(f"Board check: {n} orders, {n_trades} trades in {seconds:.1f} s "
          f"({n / seconds:.0f} orders/s over the 115200-baud link)")
    print(f"  results vs C++ model : {len(diffs)} mismatching line(s)")
    print(f"  cycle counts         : {n - cyc_bad}/{n} match the simulation model, "
          f"average {cyc_sum / n:.2f} engine cycles/order")
    ok = not diffs and cyc_bad == 0
    print("HW CHECK PASSED" if ok else "HW CHECK FAILED")
    return 0 if ok else 1


def run_manual(port):
    print("Type an order as: B|S price qty   (example: B 9 10). Empty line quits.")
    next_id = 0
    while True:
        line = input("> ").strip()
        if not line:
            return 0
        try:
            s, price, qty = line.split()
            side = {"B": 0, "S": 1}[s.upper()]
            port.write(encode_order(next_id, side, int(price), int(qty)))
        except (ValueError, KeyError):
            print("  format: B|S price(0-15) qty(1-255)")
            continue
        trades, _, status, cycles = read_reply(port)
        for (b, s_, p, q) in trades:
            print(f"  TRADE  buyer #{b}  seller #{s_}  {q} @ {p}")
        print(f"  order #{next_id}: {STATUS_NAME.get(status, status)} ({cycles} engine cycles)")
        next_id = (next_id + 1) % 256


def main():
    ap = argparse.ArgumentParser(description="Talk to the order matcher on the Basys3.")
    ap.add_argument("--port", required=True, help="serial port, e.g. COM4 (Device Manager > Ports)")
    sub = ap.add_subparsers(dest="mode", required=True)
    c = sub.add_parser("check", help="random orders, checked against the C++ model")
    c.add_argument("--orders", type=int, default=1000)
    c.add_argument("--seed", type=int, default=1)
    c.add_argument("--verbose", action="store_true", help="print the first 20 orders")
    sub.add_parser("manual", help="type orders by hand")
    args = ap.parse_args()

    port = open_port(args.port)
    try:
        code = run_check(port, args.orders, args.seed, args.verbose) if args.mode == "check" else run_manual(port)
    finally:
        port.close()
    sys.exit(code)


if __name__ == "__main__":
    main()
