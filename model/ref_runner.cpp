// ref_runner.cpp - runs the C++ reference model on a file of orders and writes the
// expected results to another file. Used instead of DPI (file-based checking).

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
