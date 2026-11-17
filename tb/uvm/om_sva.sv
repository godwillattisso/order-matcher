// om_sva.sv : assertions (SVA) that watch the design from the INSIDE.
// Each one is a rule that must hold on EVERY clock edge; if it's broken, it reports a
// UVM_ERROR immediately, at the exact time and place it happened.

// rules for one side of the book (bound into book_side) 
module book_sva
  import uvm_pkg::*;
(
  input logic       clk, rst,
  input logic       push_en, pop_en, dec_en,
  input logic [7:0] dec_qty, head_qty,
  input logic [2:0] sel_count
);
  `include "uvm_macros.svh"

  // B1: at most one of push / pop / dec in any cycle (the Day 2 interface contract)
  B1_one_op: assert property (@(posedge clk) disable iff (rst)
      $onehot0({push_en, pop_en, dec_en}))
    else `uvm_error("SVA", "B1: more than one of push/pop/dec in the same cycle")

  // B2: never push into a full level (the Day 3 bug that no output check could see)
  B2_no_push_full: assert property (@(posedge clk) disable iff (rst)
      push_en |-> (sel_count < 4))
      else `uvm_error("SVA", "B2: push into a full level")


  // B3: never pop or decrement an empty level
  B3_no_pop_empty: assert property (@(posedge clk) disable iff(rst)
      (pop_en || dec_en) |-> sel_count != 0)
      else `uvm_error("SVA", "B3: Pop or decrement is being called in a empty level")

  // B4: a decrement is always a PARTIAL fill (an exact fill must use pop)
  B4_dec_partial: assert property(@(posedge clk) disable iff(rst)
      dec_en |-> (dec_qty < head_qty))
      else `uvm_error("SVA", $sformatf("B4: dec_qty = %0d must be smaller than head_qty = %0d", dec_qty, head_qty))
endmodule

// ===================== rules for the matching engine (bound into match_engine) =====================
module engine_sva
  import uvm_pkg::*;
(
  input logic       clk, rst,
  input logic [2:0] state,
  input logic       side_r,
  input logic [3:0] price_r,
  input logic       in_ready, trade_valid, trade_ready, done_valid,
  input logic [7:0] trade_buy_id, trade_sell_id, trade_qty,
  input logic [3:0] trade_price,
  input logic       bid_valid, ask_valid,
  input logic [3:0] best_bid, best_ask
);
  `include "uvm_macros.svh"
  localparam logic [2:0] IDLE = 3'd0;   // same encoding as the enum in match_engine
  localparam logic       BUY  = 1'b0;

  // E1: while a trade is waiting (valid && !ready), it must stay valid and not change
  E1_trade_stable: assert property (@(posedge clk) disable iff (rst)
      trade_valid && !trade_ready |=> trade_valid &&
                                      $stable({trade_buy_id, trade_sell_id, trade_price, trade_qty}))
    else `uvm_error("SVA", "E1: trade changed or vanished while waiting for trade_ready")

  // E2: a trade never has quantity 0
  E2_qty_nonzero: assert property (@(posedge clk) disable iff (rst)
      trade_valid |-> trade_qty != 0)
    else `uvm_error("SVA", "E2: A trade cannot have a qty of 0")

  // E3: a trade never breaks the incoming order's price limit
  E3_price_limit: assert property (@(posedge clk) disable iff (rst)
      trade_valid |-> ((side_r == BUY) ? (trade_price <= price_r ) : trade_price >= price_r))
    else `uvm_error("SVA", "E3: Trade never breaks the Incoming order's price limit")


  // E4: between orders the book is never crossed (best bid < best ask)
  E4_not_crossed: assert property (@(posedge clk) disable iff (rst)
      (state == IDLE && (bid_valid && ask_valid)) |-> best_bid < best_ask)
    else `uvm_error("SVA", "E4: ")

  // E5: done is a one-cycle pulse
  E5_done_pulse: assert property (@(posedge clk) disable iff (rst)
      done_valid |=> !done_valid)
    else `uvm_error("SVA", "E5: done_valid high for more than one cycle")

  // E6: no unknown (X) values on the control outputs once reset is over
  E6_no_x: assert property (@(posedge clk) disable iff (rst)
      !$isunknown({state, in_ready, trade_valid, done_valid}))
    else `uvm_error("SVA", "E6: X on state or a control output after reset")
endmodule
