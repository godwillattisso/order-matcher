// match_engine.sv : the matching engine = 2 books + best-price finder + match FSM

module match_engine (
  input  logic       clk,
  input  logic       rst,            // synchronous, active-high

  // ========== Incoming Order Interface ==========
  // Order is accepted on a clock edge when in_valid && in_ready
  input  logic       in_valid,  // 1 = New order available to process
  output logic       in_ready,  // 1 = Matching engine ready to accept an order
  input  logic [7:0] in_id,     // Unique ID identifying the incoming order
  input  logic       in_side,   // Order type: 0 = BUY, 1 = SELL
  input  logic [3:0] in_price,  // Order's limit price (0–15)
  input  logic [7:0] in_qty,    // Number of units to buy/sell (1–255)

  // ========== Trade Output Interface ==========
// Trade is accepted on a clock edge when trade_valid && trade_ready

output logic       trade_valid,   // 1 = A completed trade is available
input  logic       trade_ready,   // 1 = Receiver is ready to accept the trade
output logic [7:0] trade_buy_id,  // ID of the buyer involved in the trade
output logic [7:0] trade_sell_id, // ID of the seller involved in the trade
output logic [3:0] trade_price,   // Execution price (resting order's price)
output logic [7:0] trade_qty,     // Number of units traded


// ========== Order Completion Status ==========
// Reports the final outcome of processing an incoming order

output logic       done_valid,    // 1 = Order processing finished (one-cycle pulse)
output logic [1:0] done_status,   // 0 = RESTED, 1 = FILLED, 2 = REJECTED (book full)


// ========== Top of Book (Best Available Prices) ==========
// Shows the highest BUY price and lowest SELL price in the book

output logic       bid_valid,     // 1 = At least one BUY order exists
output logic       ask_valid,     // 1 = At least one SELL order exists
output logic [3:0] best_bid,      // Highest available BUY price (0–15)
output logic [3:0] best_ask       // Lowest available SELL price (0–15)

);

  localparam logic       BUY = 1'b0, SELL = 1'b1;
  localparam logic [1:0] ACK_RESTED = 2'd0, ACK_FILLED = 2'd1, REJECT_FULL = 2'd2;
  localparam int         LEVEL_DEPTH = 4;

  // enum = named states. Vivado shows the names (IDLE, FILL, ...) in the waveform.
  typedef enum logic [2:0] {IDLE, CHECK, FILL, REST, DONE} state_t;

  state_t state, next_state;

  // ---------------- the order being worked on (latched in IDLE) ----------------
  logic [7:0] id_r;
  logic       side_r;
  logic [3:0] price_r;
  logic [7:0] rem_r;       // quantity still to fill (C++: remaining)
  logic [1:0] status_r;    // result, shown on done_status

  // ---------------- wires to/from the two books ----------------
  logic [3:0]  bid_sel, ask_sel;
  logic        bid_push, bid_pop, bid_dec, ask_push, ask_pop, ask_dec;
  logic [7:0]  bid_hid, bid_hqty, ask_hid, ask_hqty;
  logic [2:0]  bid_cnt, ask_cnt;
  logic [15:0] bid_occ, ask_occ;

  // Helper signals
  logic       opp_valid;   // opposite side has at least one order
  logic [3:0] opp_best;    // opposite side's best price
  logic [7:0] opp_hid;     // opposite side's front order at that price: id
  logic [7:0] opp_hqty;    //                                            qty
  logic       crosses;     // the best opposite price is acceptable to us
  logic [7:0] fill_qty;    // this trade's qty = min(rem_r, opp_hqty)
  logic       exact;       // the resting order is used up by this fill → pop (else dec)
  logic       last_fill;   // OUR order is used up by this fill → DONE (else CHECK)
  logic       own_full;    // our own level (our side, our price) already holds 4 orders
  logic       do_fill;     // a trade is handed over this cycle: FILL && trade_ready
  logic       do_rest;     // push our leftover this cycle: REST && !own_full

  // ---------------- your Day 2 blocks (given wiring) ----------------
  // push always adds OUR order {id_r, rem_r}. dec always subtracts fill_qty.
  book_side u_bids (.clk, .rst, .sel_price(bid_sel),
    .push_en(bid_push), .push_id(id_r), .push_qty(rem_r),
    .pop_en(bid_pop), .dec_en(bid_dec), .dec_qty(fill_qty),
    .head_id(bid_hid), .head_qty(bid_hqty), .sel_count(bid_cnt), .occ(bid_occ));

  book_side u_asks (.clk, .rst, .sel_price(ask_sel),
    .push_en(ask_push), .push_id(id_r), .push_qty(rem_r),
    .pop_en(ask_pop), .dec_en(ask_dec), .dec_qty(fill_qty),
    .head_id(ask_hid), .head_qty(ask_hqty), .sel_count(ask_cnt), .occ(ask_occ));

  best_price u_best (.bid_occ, .ask_occ, .bid_valid, .ask_valid, .best_bid, .best_ask);

  // Matching Engine Decicion Signals, These signals help the FSM decide what action to take next.
  assign opp_valid = (side_r == BUY) ? ask_valid : bid_valid;   
  assign opp_best  = (side_r == BUY) ? best_ask : best_bid; 
  assign opp_hid   = (side_r == BUY) ? ask_hid : bid_hid; 
  assign opp_hqty  = (side_r == BUY) ? ask_hqty : bid_hqty; 
  assign crosses   = opp_valid && ((side_r == BUY) ? (opp_best <= price_r) : (opp_best >= price_r));
  assign fill_qty  = (rem_r < opp_hqty) ? rem_r : opp_hqty;
  assign exact     = (fill_qty == opp_hqty);
  assign last_fill = (fill_qty == rem_r);
  assign own_full  = (side_r == BUY) ? (bid_cnt == LEVEL_DEPTH) : (ask_cnt == LEVEL_DEPTH);

  // which level each book looks at
  // Our own side looks at OUR price (to check count / push).
  // The opposite side looks at ITS best price (to read the head / pop / dec).
  assign bid_sel = (side_r == BUY)  ? price_r : best_bid;
  assign ask_sel = (side_r == SELL) ? price_r : best_ask;

  //FSM State Register
  always_ff @( posedge clk ) begin 
    if (rst)
      state <= IDLE;              // Reset FSM to IDLE, waiting for a new order
    else
      state <= next_state;        // Update current state at each rising clock edge      
  end


  // Calculating the Next state
  always_comb begin
    next_state = state;

    case (state)
        IDLE: begin
            if (in_valid)
              next_state = CHECK;
        end

        CHECK: begin
             if (crosses)
                next_state = FILL;
             else
                next_state = REST;
        end

        REST: begin
            next_state = DONE;
        end

        FILL: begin
            if (trade_ready) begin
              if (last_fill)
                next_state = DONE;
              else
                next_state = CHECK;
            end      
        end

        DONE: begin
          next_state = IDLE;
        end

        default: next_state = IDLE;
    endcase
  end


  // order registers 
  // Store incoming order + update quantity + record status.

  always_ff @( posedge clk ) begin : Order_Register
    if (state == IDLE && in_valid) begin                     // Store
      id_r <= in_id;
      side_r <= in_side;
      price_r <= in_price;
      rem_r <= in_qty;
    end
    else if (do_fill) begin                                   //Update remaining quantity after an accepted trade
      rem_r <= rem_r - fill_qty;
      if (last_fill)
        status_r <= ACK_FILLED;
    end   
    else if (state == REST) begin                              //Record final status when resting an order
        if(own_full)
          status_r <= REJECT_FULL;
        else
          status_r <= ACK_RESTED;   
    end                                                  

  end


  // Trade Execution, Order Book Control, and Output Signals

  // Execute a trade only when the receiver is ready
  assign do_fill = (state == FILL) && trade_ready;

  // Rest the remaining order only if the price level has space
  assign do_rest = (state == REST) && !own_full;

  // Accept new orders only when IDLE
  assign in_ready = (state == IDLE);

  // A trade is available while in FILL
  assign trade_valid = (state == FILL);

  // Trade information
  assign trade_buy_id  = (side_r == BUY) ? id_r : opp_hid;
  assign trade_sell_id = (side_r == SELL) ? id_r : opp_hid;
  assign trade_price   = opp_best;
  assign trade_qty     = fill_qty;

  // Push the remaining order onto its own side
  assign bid_push = do_rest && (side_r == BUY);
  assign ask_push = do_rest && (side_r == SELL);

  // Remove the opposite resting order if fully consumed
  assign bid_pop = do_fill && (side_r == SELL) && exact;
  assign ask_pop = do_fill && (side_r == BUY)  && exact;

  // Otherwise, decrease the opposite resting order's quantity
  assign bid_dec = do_fill && (side_r == SELL) && !exact;
  assign ask_dec = do_fill && (side_r == BUY)  && !exact;

  // Signal that processing the incoming order is complete
  assign done_valid  = (state == DONE);
  assign done_status = status_r;
 

endmodule
