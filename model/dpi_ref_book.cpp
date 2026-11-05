// dpi_ref_book.cpp - thin DPI-C wrapper so SystemVerilog can call the C++ model.
// Only compiled by Vivado's xsc (it provides svdpi.h). Not used in the standalone test.
#include "svdpi.h"
#include "ref_book.h"

static ob::OrderBook g_book;

extern "C" {

DPI_DLLESPEC void ref_reset() { g_book.reset(); }

// Returns number of trades produced, or -1 for an illegal order.
DPI_DLLESPEC int ref_submit(int id, int side, int price, int qty) {
    return g_book.submit(static_cast<uint8_t>(id), side, price, qty);
}

// Read trade number idx (0-based) from the last submit.
DPI_DLLESPEC void ref_get_trade(int idx, int* buy_id, int* sell_id, int* price, int* qty) {
    const auto& t = g_book.trades();
    if (idx < 0 || idx >= static_cast<int>(t.size())) {
        *buy_id = *sell_id = *price = *qty = -1;
        return;
    }
    *buy_id  = t[idx].buy_id;
    *sell_id = t[idx].sell_id;
    *price   = t[idx].price;
    *qty     = t[idx].qty;
}

// 0 = ACK_RESTED, 1 = ACK_FILLED, 2 = REJECT_FULL
DPI_DLLESPEC int ref_status() { return static_cast<int>(g_book.status()); }

DPI_DLLESPEC int ref_best_bid() { return g_book.best_bid(); }
DPI_DLLESPEC int ref_best_ask() { return g_book.best_ask(); }

}  // extern "C"
