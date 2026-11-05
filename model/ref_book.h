// ref_book.h - C++ reference model ("golden model") of the order matching engine.
// The RTL must produce exactly the same trades and statuses as this model.
#pragma once
#include <cstdint>
#include <deque>
#include <vector>

namespace ob {

constexpr int NUM_LEVELS  = 16;  // prices 0..15 (4-bit tick)
constexpr int LEVEL_DEPTH = 4;   // max resting orders per price level

enum Side   : int { BUY = 0, SELL = 1 };
enum Status : int { ACK_RESTED = 0, ACK_FILLED = 1, REJECT_FULL = 2 };

struct Order { uint8_t id;  uint8_t qty; };
struct Trade { uint8_t buy_id; uint8_t sell_id; uint8_t price; uint8_t qty; };

class OrderBook {
public:
    void reset();

    // Submit one limit order. Returns the number of trades it produced,
    // or -1 if the input is illegal (price > 15, qty == 0, bad side).
    int submit(uint8_t id, int side, int price, int qty);

    const std::vector<Trade>& trades() const { return trades_; }  // trades from the LAST submit
    Status status() const { return status_; }                     // status of the LAST submit

    int best_bid() const;                     // highest bid price, -1 if no bids
    int best_ask() const;                     // lowest ask price,  -1 if no asks
    int level_count(int side, int price) const;

private:
    std::deque<Order> bids_[NUM_LEVELS];      // front() = oldest = fills first
    std::deque<Order> asks_[NUM_LEVELS];
    std::vector<Trade> trades_;
    Status status_ = ACK_RESTED;
};

}  // namespace ob
