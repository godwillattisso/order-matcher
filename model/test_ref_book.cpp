// test_ref_book.cpp - standalone tests for the reference model (no Vivado needed).
// Build:  g++ -std=c++14 -Wall -o test_ref_book test_ref_book.cpp ref_book.cpp
// Run:    ./test_ref_book
#include "ref_book.h"
#include <cstdio>
#include <random>

using namespace ob;

static int g_fail = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("  FAIL line %d: %s\n", __LINE__, #cond); ++g_fail; } } while (0)

// Checks trade number idx from the last submit. Safe if fewer trades exist.
static bool trade_is(const OrderBook& ob, size_t idx, int b, int s, int p, int q) {
    if (idx >= ob.trades().size()) return false;
    const Trade& t = ob.trades()[idx];
    return t.buy_id == b && t.sell_id == s && t.price == p && t.qty == q;
}

static void test_rest_on_empty_book() {
    std::printf("test_rest_on_empty_book\n");
    OrderBook ob; ob.reset();
    CHECK(ob.submit(1, BUY, 10, 5) == 0);
    CHECK(ob.status() == ACK_RESTED);
    CHECK(ob.best_bid() == 10);
    CHECK(ob.best_ask() == -1);
}

static void test_full_fill() {
    std::printf("test_full_fill\n");
    OrderBook ob; ob.reset();
    ob.submit(1, BUY, 10, 5);
    CHECK(ob.submit(2, SELL, 10, 5) == 1);
    CHECK(trade_is(ob, 0, 1, 2, 10, 5));
    CHECK(ob.status() == ACK_FILLED);
    CHECK(ob.best_bid() == -1 && ob.best_ask() == -1);
}

// Rule 3: trade happens at the RESTING price (10), not the incoming price (9).
static void test_partial_fill_uses_resting_price() {
    std::printf("test_partial_fill_uses_resting_price\n");
    OrderBook ob; ob.reset();
    ob.submit(1, BUY, 10, 5);
    CHECK(ob.submit(2, SELL, 9, 8) == 1);
    CHECK(trade_is(ob, 0, 1, 2, 10, 5));
    CHECK(ob.status() == ACK_RESTED);        // 3 left over, rests at ask 9
    CHECK(ob.best_ask() == 9);
    CHECK(ob.best_bid() == -1);
}

// Rule 2: same price -> oldest first.
static void test_time_priority() {
    std::printf("test_time_priority\n");
    OrderBook ob; ob.reset();
    ob.submit(1, BUY, 10, 3);
    ob.submit(2, BUY, 10, 3);
    CHECK(ob.submit(3, SELL, 10, 4) == 2);
    CHECK(trade_is(ob, 0, 1, 3, 10, 3));
    CHECK(trade_is(ob, 1, 2, 3, 10, 1));
    CHECK(ob.status() == ACK_FILLED);
    CHECK(ob.level_count(BUY, 10) == 1);     // order 2 still has 2 left
}

// Rule 1: one big order sweeps several levels, best price first.
static void test_sweep_levels() {
    std::printf("test_sweep_levels\n");
    OrderBook ob; ob.reset();
    ob.submit(1, SELL, 5, 2);
    ob.submit(2, SELL, 6, 2);
    ob.submit(3, SELL, 7, 2);
    CHECK(ob.submit(4, BUY, 6, 10) == 2);    // takes 5 and 6, not 7
    CHECK(trade_is(ob, 0, 4, 1, 5, 2));
    CHECK(trade_is(ob, 1, 4, 2, 6, 2));
    CHECK(ob.status() == ACK_RESTED);        // 6 left, rests at bid 6
    CHECK(ob.best_bid() == 6);
    CHECK(ob.best_ask() == 7);
}

// Rule 5: 5th order at a full level is rejected and nothing changes.
static void test_level_full_reject() {
    std::printf("test_level_full_reject\n");
    OrderBook ob; ob.reset();
    for (int i = 1; i <= 4; ++i) { ob.submit(i, BUY, 3, 1); CHECK(ob.status() == ACK_RESTED); }
    CHECK(ob.submit(5, BUY, 3, 1) == 0);
    CHECK(ob.status() == REJECT_FULL);
    CHECK(ob.level_count(BUY, 3) == 4);
}

static void test_illegal_inputs() {
    std::printf("test_illegal_inputs\n");
    OrderBook ob; ob.reset();
    CHECK(ob.submit(1, BUY, 16, 5) == -1);   // price out of range
    CHECK(ob.submit(1, BUY, 5, 0) == -1);    // zero quantity
    CHECK(ob.submit(1, 7, 5, 5) == -1);      // bad side
    CHECK(ob.best_bid() == -1 && ob.best_ask() == -1);
}

// 20,000 random orders; check rules that must ALWAYS hold.
// These same rules become SystemVerilog assertions on Day 5.
static void test_random_invariants() {
    std::printf("test_random_invariants\n");
    OrderBook ob; ob.reset();
    std::mt19937 rng(12345);
    std::uniform_int_distribution<int> side_d(0, 1), price_d(0, 15), qty_d(1, 255);
    int fills = 0, rests = 0, rejects = 0, errors_before = g_fail;

    for (int i = 0; i < 20000 && g_fail - errors_before < 5; ++i) {
        int side = side_d(rng), price = price_d(rng), qty = qty_d(rng);
        int n = ob.submit(static_cast<uint8_t>(i), side, price, qty);
        CHECK(n >= 0);

        int traded = 0;
        for (const Trade& t : ob.trades()) {
            CHECK(t.qty > 0);
            traded += t.qty;
            if (side == BUY) CHECK(t.price <= price);   // buyer never pays above limit
            else             CHECK(t.price >= price);   // seller never sells below limit
        }
        CHECK(traded <= qty);
        if (ob.status() == ACK_FILLED) { CHECK(traded == qty); ++fills; }
        if (ob.status() == ACK_RESTED) { CHECK(traded <  qty); ++rests; }
        if (ob.status() == REJECT_FULL) { CHECK(n == 0); ++rejects; }

        int bb = ob.best_bid(), ba = ob.best_ask();
        if (bb >= 0 && ba >= 0) CHECK(bb < ba);          // book never crossed
        for (int p = 0; p < NUM_LEVELS; ++p) {
            CHECK(ob.level_count(BUY, p)  <= LEVEL_DEPTH);
            CHECK(ob.level_count(SELL, p) <= LEVEL_DEPTH);
        }
    }
    std::printf("  outcomes: %d filled, %d rested, %d rejected\n", fills, rests, rejects);
}

int main() {
    test_rest_on_empty_book();
    test_full_fill();
    test_partial_fill_uses_resting_price();
    test_time_priority();
    test_sweep_levels();
    test_level_full_reject();
    test_illegal_inputs();
    test_random_invariants();
    if (g_fail == 0) std::printf("\nALL TESTS PASSED\n");
    else             std::printf("\n%d CHECK(S) FAILED\n", g_fail);
    return g_fail == 0 ? 0 : 1;
}
