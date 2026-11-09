// ref_runner.cpp - runs the C++ reference model on a file of orders and writes the
// expected results to another file. Used instead of DPI (file-based checking).
//
// Usage:   ref_runner.exe <orders_in.txt> <expected_out.txt>
//
// Input  (one order per line):        <id> <side> <price> <qty>
//                                      side: 0 = BUY, 1 = SELL
// Output (for each order, in order):  S <order_index> <num_trades> <status>
//                                      then one line per trade:
//                                      T <order_index> <buy_id> <sell_id> <price> <qty>
//                                      status: 0 = ACK_RESTED, 1 = ACK_FILLED, 2 = REJECT_FULL
//                                      num_trades = -1 means the order was illegal
//
// Build (MSYS2 UCRT64 terminal, from the model folder):
//   g++ -std=c++14 -Wall -static -o ref_runner ref_runner.cpp ref_book.cpp
// -static makes ref_runner.exe self-contained, so it runs from a normal Command
// Prompt (and from the simulator) without MSYS2 on the Windows PATH.
#include "ref_book.h"
#include <cstdio>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "usage: ref_runner <orders_in.txt> <expected_out.txt>\n");
        return 2;
    }
    std::FILE* in = std::fopen(argv[1], "r");
    if (!in)  { std::fprintf(stderr, "ref_runner: cannot open %s\n", argv[1]); return 2; }
    std::FILE* out = std::fopen(argv[2], "w");
    if (!out) { std::fprintf(stderr, "ref_runner: cannot create %s\n", argv[2]); std::fclose(in); return 2; }

    ob::OrderBook book;
    book.reset();

    int id, side, price, qty, idx = 0;
    while (std::fscanf(in, "%d %d %d %d", &id, &side, &price, &qty) == 4) {
        int n = book.submit(static_cast<uint8_t>(id), side, price, qty);
        std::fprintf(out, "S %d %d %d\n", idx, n, n < 0 ? -1 : static_cast<int>(book.status()));
        if (n > 0) {
            for (const ob::Trade& t : book.trades()) {
                std::fprintf(out, "T %d %d %d %d %d\n", idx, t.buy_id, t.sell_id, t.price, t.qty);
            }
        }
        ++idx;
    }
    std::fclose(in);
    std::fclose(out);
    std::printf("ref_runner: processed %d orders\n", idx);
    return 0;
}
