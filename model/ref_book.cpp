// ref_book.cpp - YOUR implementation of the reference order book.
//
// Matching rules (this is the spec):
//  1. Price priority: a buy hits the LOWEST ask first; a sell hits the HIGHEST bid first.
//  2. Time priority: same price -> oldest order fills first (front of the deque).
//  3. Trade price = price of the order that was already resting in the book.
//  4. Unfilled remainder rests at the incoming order's price (push to the back of that level).
//  5. If that price level already holds LEVEL_DEPTH (4) orders, status = REJECT_FULL
//     and the remainder is NOT added.
//
// Done when test_ref_book.exe prints ALL TESTS PASSED.

#include "ref_book.h"
#include <algorithm>

namespace ob
{

    // Given: clears the book.
    void OrderBook::reset()
    {
        for (int p = 0; p < NUM_LEVELS; ++p)
        {
            bids_[p].clear();
            asks_[p].clear();
        }
        trades_.clear();
        status_ = ACK_RESTED;
    }

    // Given: number of orders resting at one price on one side.
    int OrderBook::level_count(int side, int price) const
    {
        if (price < 0 || price >= NUM_LEVELS)
            return 0;
        return static_cast<int>(side == BUY ? bids_[price].size() : asks_[price].size());
    }

    // return the HIGHEST price p where bids_[p] is not empty, or -1 if there are no bids.
    int OrderBook::best_bid() const
    {
        for (int p = NUM_LEVELS - 1; p >= 0; --p)
        {
            if (!bids_[p].empty())
            {
                return p;
            }
        }
        return -1;
    }

    // return the LOWEST price p where asks_[p] is not empty, or -1 if there are no asks.
    int OrderBook::best_ask() const
    {
        for (int p = 0; p < NUM_LEVELS; ++p)
            if (!asks_[p].empty())
            {
                return p;
            }
        return -1;
    }

    // Return the number of trades it produced, or -1 for illegal input.
    int OrderBook::submit(uint8_t id, int side, int price, int qty)
    {
        trades_.clear();     // trades_ only holds trades from THIS order
        int remaining = qty; // As trades reduce this will be the remainder

        // return -1 if side isn't BUY/SELL, price isn't 0..15, or qty isn't 1..255.
        if (side != BUY && side != SELL)
            return -1; // Makes sure only buying or selling are the only options
        if (price < 0 || price >= NUM_LEVELS)
            return -1; // Makes sure that the price fits in the max array numbers
        if (qty <= 0 || qty > 255)
            return -1; // Makes sure that the quantty of shares can fit in a 8 bit max which is 255

        if (side == BUY)
        {
            while (remaining > 0)
            {
                int ask = best_ask(); // gets the cheapest price in the queue
                if (ask == -1 || ask > price)
                    break;

                Order &resting = asks_[ask].front();                           // gets the older seller, which will be at the front of the queue
                int fill = std::min(remaining, static_cast<int>(resting.qty)); // Gets the min value of shares

                trades_.push_back({id, resting.id,               // Adds the buyer_ID, Seller_ID, min Price and qty to the trades vector
                                   static_cast<uint8_t>(ask),    // Price = sellers price
                                   static_cast<uint8_t>(fill)}); // min qty

                remaining -= fill;   // Gives us the remainder
                resting.qty -= fill; // Reduces the resting seller's remaining qty

                if (resting.qty == 0)
                {
                    asks_[ask].pop_front();
                } // Pop the seller out of the queue
            }
        }
        else
        {
            while (remaining > 0)
            {
                int bid = best_bid(); // gets the highest price in the queue
                if (bid == -1 || bid < price)
                    break;

                Order &resting = bids_[bid].front();                           // gets the older buyer, which will be at the front of the queue
                int fill = std::min(remaining, static_cast<int>(resting.qty)); // Gets the min value of shares

                trades_.push_back({resting.id, id,               // Adds the Sellers_ID, Buyers_ID, min Price and qty to the trades vector
                                   static_cast<uint8_t>(bid),    // Price = Buyer price
                                   static_cast<uint8_t>(fill)}); // min qty

                remaining -= fill;   // Gives us the remainder
                resting.qty -= fill; // Reduces the resting buyers remaning qty

                if (resting.qty == 0)
                {
                    bids_[bid].pop_front();
                } // Pop the Buyer out of the queue
            }
        }

        // Setting Status for after theres remainders

        if (remaining == 0)
        {
            status_ = ACK_FILLED; // if theres no shares left
        }
        else
        {
            std::deque<Order> &level = (side == BUY) ? bids_[price] : asks_[price]; // Picking what queue you are in Buyer or Seller
            if (static_cast<int>(level.size()) >= LEVEL_DEPTH)
            { // Checking if the the size of the position your are at is not full
                status_ = REJECT_FULL;
            }
            else
            {
                level.push_back({id, static_cast<uint8_t>(remaining)}); // will push the remaining shares into the queue
                status_ = ACK_RESTED;
            }
        }
        return static_cast<int>(trades_.size());
    }

} // namespace ob
