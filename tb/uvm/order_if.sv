// order_if.sv : the bundle of wires between the testbench and the match engine.
// GIVEN FILE. One interface instead of 20 separate wires: the driver and monitor
// get a handle to it ("virtual interface") and drive/watch the DUT through it.
interface order_if (input logic clk);
  logic       rst;

  // order in
  logic       in_valid, in_ready, in_side;
  logic [7:0] in_id, in_qty;
  logic [3:0] in_price;

  // trade out
  logic       trade_valid, trade_ready;
  logic [7:0] trade_buy_id, trade_sell_id, trade_qty;
  logic [3:0] trade_price;

  // done
  logic       done_valid;
  logic [1:0] done_status;

  // top of book
  logic       bid_valid, ask_valid;
  logic [3:0] best_bid, best_ask;
endinterface
