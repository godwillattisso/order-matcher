// ref_book.cpp - matching rules:
//  1. Price priority: a buy hits the LOWEST ask first; a sell hits the HIGHEST bid first.
//  2. Time priority: same price -> oldest order fills first (FIFO per level).
//  3. Trade price = price of the order that was already resting in the book.
//  4. Unfilled remainder rests at the incoming order's price.
//  5. If that price level already holds 4 orders, the remainder is rejected (REJECT_FULL).
#include "ref_book.h"
#include <algorithm>

namespace ob {

void OrderBook::reset() {
    for (int p = 0; p < NUM_LEVELS; ++p) { bids_[p].clear(); asks_[p].clear(); }
    trades_.clear();
    status_ = ACK_RESTED;
}

int OrderBook::best_bid() const {
    for (int p = NUM_LEVELS - 1; p >= 0; --p) if (!bids_[p].empty()) return p;
    return -1;
}

int OrderBook::best_ask() const {
    for (int p = 0; p < NUM_LEVELS; ++p) if (!asks_[p].empty()) return p;
    return -1;
}

int OrderBook::level_count(int side, int price) const {
    if (price < 0 || price >= NUM_LEVELS) return 0;
    return static_cast<int>(side == BUY ? bids_[price].size() : asks_[price].size());
}

int OrderBook::submit(uint8_t id, int side, int price, int qty) {
    trades_.clear();
    if (side != BUY && side != SELL)        return -1;
    if (price < 0 || price >= NUM_LEVELS)   return -1;
    if (qty <= 0 || qty > 255)              return -1;

    int remaining = qty;

    if (side == BUY) {
        while (remaining > 0) {
            int ask = best_ask();
            if (ask < 0 || ask > price) break;           // nothing cheap enough
            Order& resting = asks_[ask].front();
            int fill = std::min(remaining, static_cast<int>(resting.qty));
            trades_.push_back({id, resting.id, static_cast<uint8_t>(ask), static_cast<uint8_t>(fill)});
            remaining   -= fill;
            resting.qty -= static_cast<uint8_t>(fill);
            if (resting.qty == 0) asks_[ask].pop_front();
        }
    } else {
        while (remaining > 0) {
            int bid = best_bid();
            if (bid < 0 || bid < price) break;           // nobody pays enough
            Order& resting = bids_[bid].front();
            int fill = std::min(remaining, static_cast<int>(resting.qty));
            trades_.push_back({resting.id, id, static_cast<uint8_t>(bid), static_cast<uint8_t>(fill)});
            remaining   -= fill;
            resting.qty -= static_cast<uint8_t>(fill);
            if (resting.qty == 0) bids_[bid].pop_front();
        }
    }

    if (remaining == 0) {
        status_ = ACK_FILLED;
    } else {
        std::deque<Order>& level = (side == BUY) ? bids_[price] : asks_[price];
        if (static_cast<int>(level.size()) >= LEVEL_DEPTH) {
            status_ = REJECT_FULL;
        } else {
            level.push_back({id, static_cast<uint8_t>(remaining)});
            status_ = ACK_RESTED;
        }
    }
    return static_cast<int>(trades_.size());
}

}  // namespace ob
