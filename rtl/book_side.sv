// book_side.sv : ONE side of the order book (used twice: once for bids, once for asks)
//
// Hardware version of ONE of these from your C++ model:
//     std::deque<Order> bids_[NUM_LEVELS];   (or asks_[NUM_LEVELS])
//
//               sel_price (which level every port talks to)
//                    │
//   push ──────────► ┌───────────────────────────────┐ ──► head_id, head_qty (front of sel level)
//   pop  ──────────► │ 16 levels x 4 slots {id, qty} │ ──► sel_count         (orders at sel level)
//   dec  ──────────► │ + count[16]                   │ ──► occ[15:0]         (1 = level not empty)
//                    └───────────────────────────────┘
//
// RULES (the Day 3 FSM promises these, so you don't need to handle the alternatives):
//   * At most ONE of push_en / pop_en / dec_en is 1 in any clock cycle.
//   * push_en is only used when the level has room. If it's full anyway: do nothing.
//   * pop_en / dec_en are only used when the level isn't empty. If it's empty anyway: do nothing.
//   * dec_qty is always smaller than head_qty (an exact fill uses pop instead).
//   * head_id / head_qty are don't-care when sel_count == 0.
//
// YOU WRITE: the 4 TODO blocks below. Don't change the port list (the testbench uses it).

module book_side #(
  parameter int NUM_LEVELS  = 16,   // must match NUM_LEVELS  in ref_book.h
  parameter int LEVEL_DEPTH = 4     // must match LEVEL_DEPTH in ref_book.h
)(
  input  logic                  clk,
  input  logic                  rst,        // synchronous, active-high: empties every level

  input  logic [3:0]            sel_price,  // level that push / pop / dec / head / count use

  input  logic                  push_en,    // add {push_id, push_qty} to the BACK of level sel_price
  input  logic [7:0]            push_id,
  input  logic [7:0]            push_qty,

  input  logic                  pop_en,     // remove the FRONT order of level sel_price

  input  logic                  dec_en,     // front order's qty -= dec_qty (a partial fill)
  input  logic [7:0]            dec_qty,

  output logic [7:0]            head_id,    // front (oldest) order of level sel_price
  output logic [7:0]            head_qty,
  output logic [2:0]            sel_count,  // number of orders at level sel_price (0..4)
  output logic [NUM_LEVELS-1:0] occ         // occ[p] = 1 when level p has at least one order
);

  // ---------------- storage ----------------
  // Slot 0 is the FRONT (oldest). Valid slots are 0 .. count[level]-1.
  logic [7:0] id_mem  [NUM_LEVELS][LEVEL_DEPTH];
  logic [7:0] qty_mem [NUM_LEVELS][LEVEL_DEPTH];
  logic [2:0] count   [NUM_LEVELS];

  // ---------------- TODO 1: the clocked block (push / pop / dec / reset) ----------------
  // always_ff @(posedge clk) begin
  //   if (rst)          -> set every count[l] to 0 (a for loop). The id/qty slots don't need clearing. Why?
  //   else if (push_en) -> if the level isn't full: write id and qty into slot count[sel_price],
  //                        then count + 1
  //   else if (pop_en)  -> if the level isn't empty: shift slots down by one (slot i gets slot i+1),
  //                        then count - 1
  //   else if (dec_en)  -> if the level isn't empty: slot 0's qty minus dec_qty
  // end
  // Use <= (non-blocking) for everything inside always_ff.


  // ---------------- TODO 2: head outputs (combinational) ----------------
  // head_id and head_qty = slot 0 of level sel_price. One assign each.
  assign head_id  = '0;   // replace
  assign head_qty = '0;   // replace

  // ---------------- TODO 3: count output ----------------
  assign sel_count = '0;  // replace

  // ---------------- TODO 4: occupancy bitmap ----------------
  // occ[l] = 1 when count[l] is not 0. Use always_comb with a for loop over l.
  assign occ = '0;        // replace (delete this line when you write the always_comb)

endmodule
