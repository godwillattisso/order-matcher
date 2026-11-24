#!/usr/bin/env python3
"""board_demo.py : scripted, slow-paced demo of the order matcher on the Basys3 (for the showcase video).

Sends a fixed sequence of orders one at a time, with a pause between them so the camera can catch
the 7-segment display and LEDs changing. For every order it prints:
  - a one-line caption (what this order demonstrates)
  - the order, every trade the board reports, and the final status
  - "Display:" = what the 7-segment display should be showing now (best bid / best ask)
At the end: a results summary, the resting book, and a check of every board answer against the
C++ reference model (same check as `board_client.py check`).

    python scripts\\board_demo.py --port COM5                 (2.5 s between orders)
    python scripts\\board_demo.py --port COM5 --delay 4       (slower)
    python scripts\\board_demo.py --port COM5 --step          (press Enter before each order)

The "Display:" line is NOT a second model: it is rebuilt only from the board's own replies
(rests, trades), so it shows what the hardware did.
"""

import argparse
import subprocess
import sys
import time

from board_client import (MODEL, OUT_DIR, STATUS_NAME, compare_files, encode_order,
                          expected_cycles, open_port, read_reply)

BUY, SELL = 0, 1

# (caption, side, price, qty). Each caption is printed before its order is sent.
DEMO = [
    ("Buy 10 @ 9: nothing to match, it rests on the bid side", BUY, 9, 10),
    ("Buy 5 @ 8: rests behind the better bid at 9",            BUY, 8, 5),
    ("Sell 5 @ 11: rests on the ask side",                     SELL, 11, 5),
    ("Sell 3 @ 12: rests behind the better ask at 11",         SELL, 12, 3),
    ("Sell 4 @ 9: crosses the bid -> trade at 9",              SELL, 9, 4),
    ("Buy 2 @ 11: crosses the ask -> trade at 11",             BUY, 11, 2),
    ("WHALE sell 20 @ 8: sweeps two bid levels, rest stays",   SELL, 8, 20),
    ("WHALE buy 15 @ 12: sweeps three ask levels",             BUY, 12, 15),
    ("Buy 3 @ 10: rests",                                      BUY, 10, 3),
    ("Buy 4 @ 10: same price, queued BEHIND the first",        BUY, 10, 4),
    ("Sell 5 @ 10: time priority -> first buyer fills first",  SELL, 10, 5),
    ("Buy 1 @ 7  (filling level 7: slot 1 of 4)",              BUY, 7, 1),
    ("Buy 1 @ 7  (slot 2 of 4)",                               BUY, 7, 1),
    ("Buy 1 @ 7  (slot 3 of 4)",                               BUY, 7, 1),
    ("Buy 1 @ 7  (slot 4 of 4: level now full)",               BUY, 7, 1),
    ("Buy 1 @ 7  (level full -> board must REJECT it)",        BUY, 7, 1),
]


def side_name(side):
    return "BUY " if side == BUY else "SELL"


def display_text(book):
    """What the 7-segment display shows: best bid (left) and best ask (right), '--' if empty."""
    bids = [p for (s, p, q) in book.values() if s == BUY and q > 0]
    asks = [p for (s, p, q) in book.values() if s == SELL and q > 0]
    bid = f"{max(bids):>2}" if bids else "--"
    ask = f"{min(asks):>2}" if asks else "--"
    return f"{bid} {ask}"


def update_book(book, oid, side, price, qty, trades, status):
    """Rebuild the resting book from the board's replies only."""
    for (b, s, p, q) in trades:
        for rid in (b, s):
            if rid in book and rid != oid:          # the incoming order isn't resting yet
                rs, rp, rq = book[rid]
                book[rid] = (rs, rp, rq - q)
                if rq - q <= 0:
                    del book[rid]
    if status == 0:                                 # RESTED: what's left goes in the book
        left = qty - sum(q for (_, _, _, q) in trades)
        if left > 0:
            book[oid] = (side, price, left)


def print_book(book):
    if not book:
        print("  (empty)")
        return
    for side, label in ((SELL, "ASK"), (BUY, "BID")):
        prices = sorted({p for (s, p, q) in book.values() if s == side}, reverse=True)
        for p in prices:
            queue = [f"#{oid}:{q}" for oid, (s, pp, q) in book.items() if s == side and pp == p]
            print(f"  {label} {p:>2} | " + "  ".join(queue))


def run_demo(port, delay, step):
    input("Press the centre button (btnC) to clear the board's book, then press Enter to start...")
    print()
    book, orders, hw_lines = {}, [], []
    counts = {0: 0, 1: 0, 2: 0}
    n_trades, volume, cyc_bad = 0, 0, 0

    for idx, (caption, side, price, qty) in enumerate(DEMO):
        oid = idx % 256
        if step:
            input(f"[{idx + 1}/{len(DEMO)}] {caption}   (Enter to send)")
        else:
            print(f"[{idx + 1}/{len(DEMO)}] {caption}")
        print(f"  ORDER  #{oid:<3} {side_name(side)} {qty:>3} @ {price}")

        port.write(encode_order(oid, side, price, qty))
        trades, done_id, status, cycles = read_reply(port)
        if done_id != oid:
            raise RuntimeError(f"board answered for id {done_id}, expected {oid}")

        for (b, s, p, q) in trades:
            print(f"  TRADE  {q:>3} @ {p:<2}  buyer #{b}  seller #{s}")
        print(f"  -> {STATUS_NAME.get(status, status)}, {len(trades)} trade(s), {cycles} engine cycles")

        update_book(book, oid, side, price, qty, trades, status)
        print(f"  Display:  [{display_text(book)}]")
        print()

        orders.append((oid, side, price, qty))
        hw_lines.append(f"S {idx} {len(trades)} {status}")
        hw_lines += [f"T {idx} {b} {s} {p} {q}" for (b, s, p, q) in trades]
        counts[status] = counts.get(status, 0) + 1
        n_trades += len(trades)
        volume += sum(q for (_, _, _, q) in trades)
        if cycles != expected_cycles(status, len(trades)):
            cyc_bad += 1
        if not step and idx < len(DEMO) - 1:
            time.sleep(delay)

    # ---- results ----
    n = len(DEMO)
    print("=" * 52)
    print("RESULTS")
    print("=" * 52)
    print(f"  Orders sent     : {n}")
    print(f"  Rested / Filled / Rejected : {counts[0]} / {counts[1]} / {counts[2]}")
    print(f"  Trades          : {n_trades}  ({volume} shares traded)")
    print(f"  Final display   : [{display_text(book)}]")
    print("  Resting book:")
    print_book(book)

    # Same hardware-vs-C++ check as `board_client.py check`
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    orders_path, hw_path, ref_path = OUT_DIR / "demo_orders.txt", OUT_DIR / "demo_hw.txt", OUT_DIR / "demo_expected.txt"
    orders_path.write_text("".join(f"{o} {s} {p} {q}\n" for (o, s, p, q) in orders))
    hw_path.write_text("\n".join(hw_lines) + "\n")
    if not MODEL.exists():
        print(f"\n  (C++ check skipped: {MODEL} not found)")
        return 0
    subprocess.run([str(MODEL), str(orders_path), str(ref_path)], check=True, stdout=subprocess.DEVNULL)
    diffs = compare_files(hw_path, ref_path)
    for (line, a, b) in diffs[:10]:
        print(f"  MISMATCH line {line}: board='{a}'  C++='{b}'")
    print()
    print(f"  Board vs C++ model : {len(diffs)} mismatch(es)")
    print(f"  Cycle counts       : {n - cyc_bad}/{n} match the simulation model")
    ok = not diffs and cyc_bad == 0
    print("DEMO CHECK PASSED" if ok else "DEMO CHECK FAILED")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="Scripted demo of the order matcher on the Basys3.")
    ap.add_argument("--port", required=True, help="serial port, e.g. COM4")
    ap.add_argument("--delay", type=float, default=2.5, help="seconds between orders (default 2.5)")
    ap.add_argument("--step", action="store_true", help="press Enter before each order instead of a timer")
    args = ap.parse_args()

    port = open_port(args.port)
    try:
        code = run_demo(port, args.delay, args.step)
    finally:
        port.close()
    sys.exit(code)


if __name__ == "__main__":
    main()
