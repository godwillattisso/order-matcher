// tb_engine.sv : Day 3 test for match_engine (directed + random)
// GIVEN FILE: you don't need to edit it. Read it to see how your FSM is used.

module tb_engine;
  timeunit 1ns; timeprecision 1ps;   // #5 = 5 ns

  localparam int BUY = 0, SELL = 1;
  localparam int ACK_RESTED = 0, ACK_FILLED = 1, REJECT_FULL = 2;
  localparam int TIMEOUT = 300;      // cycles to wait before declaring the DUT stuck

  // ---------------- clock, reset, DUT ----------------
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst;

  logic       in_valid, in_ready, in_side;
  logic [7:0] in_id, in_qty;
  logic [3:0] in_price;
  logic       trade_valid, trade_ready;
  logic [7:0] trade_buy_id, trade_sell_id, trade_qty;
  logic [3:0] trade_price;
  logic       done_valid;
  logic [1:0] done_status;
  logic       bid_valid, ask_valid;
  logic [3:0] best_bid, best_ask;

  match_engine dut (.*);

  // ---------------- what the DUT produced for the current order ----------------
  int         got_n;
  logic [7:0] got_buy [64], got_sell [64], got_qty [64];
  logic [3:0] got_price [64];
  bit         got_done;
  int         got_status;
  int         cycles;                 // clock edges from order accepted to done

  always @(posedge clk) begin
    if (!rst && trade_valid && trade_ready && got_n < 64) begin
      got_buy[got_n]   <= trade_buy_id;
      got_sell[got_n]  <= trade_sell_id;
      got_price[got_n] <= trade_price;
      got_qty[got_n]   <= trade_qty;
      got_n            <= got_n + 1;
    end
    if (!rst && done_valid) begin
      got_done   <= 1;
      got_status <= done_status;
    end
  end

  // trade_ready control: 0 = always ready, 1 = random back-pressure
  int bp_mode = 0;
  always @(negedge clk) trade_ready <= (bp_mode == 0) ? 1'b1 : ($urandom_range(3, 0) != 0);

  // ---------------- model: what SHOULD happen (same rules as ref_book.cpp) ----------------
  int m_id  [2][16][4];
  int m_qty [2][16][4];
  int m_cnt [2][16];
  int exp_n, exp_status;
  int exp_buy [64], exp_sell [64], exp_price [64], exp_qty [64];

  function automatic int m_best(input int side);   // -1 if empty
    int b;
    b = -1;
    if (side == BUY) begin for (int p = 0; p < 16; p++)  if (m_cnt[BUY][p]  > 0) b = p; end
    else             begin for (int p = 15; p >= 0; p--) if (m_cnt[SELL][p] > 0) b = p; end
    return b;
  endfunction

  function automatic void m_reset();
    for (int s = 0; s < 2; s++) for (int p = 0; p < 16; p++) m_cnt[s][p] = 0;
  endfunction

  function automatic void model_submit(input int id, input int side, input int price, input int qty);
    int rem, opp, bp, f;
    bit go;
    rem = qty; opp = 1 - side; exp_n = 0; go = 1;
    while (rem > 0 && go) begin
      bp = m_best(opp);
      if (bp == -1)                          go = 0;
      else if (side == BUY  && bp > price)   go = 0;
      else if (side == SELL && bp < price)   go = 0;
      else begin
        f = (rem < m_qty[opp][bp][0]) ? rem : m_qty[opp][bp][0];
        exp_buy[exp_n]   = (side == BUY) ? id : m_id[opp][bp][0];
        exp_sell[exp_n]  = (side == BUY) ? m_id[opp][bp][0] : id;
        exp_price[exp_n] = bp;
        exp_qty[exp_n]   = f;
        exp_n++;
        rem -= f;
        m_qty[opp][bp][0] -= f;
        if (m_qty[opp][bp][0] == 0) begin
          for (int i = 0; i < 3; i++) begin
            m_id[opp][bp][i]  = m_id[opp][bp][i+1];
            m_qty[opp][bp][i] = m_qty[opp][bp][i+1];
          end
          m_cnt[opp][bp]--;
        end
      end
    end
    if (rem == 0)                      exp_status = ACK_FILLED;
    else if (m_cnt[side][price] == 4)  exp_status = REJECT_FULL;
    else begin
      m_id [side][price][m_cnt[side][price]] = id;
      m_qty[side][price][m_cnt[side][price]] = rem;
      m_cnt[side][price]++;
      exp_status = ACK_RESTED;
    end
  endfunction

  // ---------------- checking ----------------
  int errors = 0, checks = 0, orders = 0;
  int total_trades = 0, total_cycles = 0;
  int n_status [3];
  bit stuck = 0;

  task automatic check(input bit ok, input string what);
    checks++;
    if (!ok) begin
      errors++;
      $display("FAIL #%0d at %0t: %s", errors, $time, what);
    end
  endtask

  function automatic string st_name(input int s);
    case (s) 0: return "RESTED"; 1: return "FILLED"; 2: return "REJECT_FULL"; default: return "???"; endcase
  endfunction

  // Send one order, wait for its done pulse, compare everything with the model.
  task automatic send_order(input string tag, input int id, input int side, input int price, input int qty);
    int wait_cycles;
    string o, sd;
    if (side == BUY) sd = "BUY"; else sd = "SELL";
    o = $sformatf("%s order %0d (%s %0d @ %0d)", tag, id, sd, qty, price);
    if (!stuck) begin
      // 1. wait until the DUT is ready for a new order
      wait_cycles = 0;
      @(negedge clk);
      while (!in_ready && wait_cycles < TIMEOUT) begin @(negedge clk); wait_cycles++; end
      if (!in_ready) begin
        check(0, $sformatf("%s: in_ready never went high (FSM stuck?)", o));
        stuck = 1;
      end
    end

    if (!stuck) begin
      // 2. drive the order for exactly one clock edge (in_ready is 1, so it's accepted)
      got_n = 0; got_done = 0; cycles = 0;
      in_valid = 1; in_id = id; in_side = side; in_price = price; in_qty = qty;
      @(negedge clk);
      in_valid = 0; in_id = 'x; in_side = 'x; in_price = 'x; in_qty = 'x;   // X = "don't use this"
      cycles = 1;

      // 3. wait for the done pulse
      while (!got_done && cycles < TIMEOUT) begin @(negedge clk); cycles++; end
      if (!got_done) begin
        check(0, $sformatf("%s: no done_valid within %0d cycles (FSM stuck?)", o, TIMEOUT));
        stuck = 1;
      end
    end

    if (!stuck) begin
      // 4. compare with the model
      model_submit(id, side, price, qty);
      orders++;
      total_trades += exp_n;
      total_cycles += cycles;
      n_status[exp_status]++;
      check(got_n == exp_n, $sformatf("%s: %0d trades, expected %0d", o, got_n, exp_n));
      for (int k = 0; k < exp_n && k < got_n; k++)
        check(got_buy[k] == exp_buy[k] && got_sell[k] == exp_sell[k] &&
              got_price[k] == exp_price[k] && got_qty[k] == exp_qty[k],
              $sformatf("%s: trade %0d is buy=%0d sell=%0d price=%0d qty=%0d, expected buy=%0d sell=%0d price=%0d qty=%0d",
                        o, k, got_buy[k], got_sell[k], got_price[k], got_qty[k],
                        exp_buy[k], exp_sell[k], exp_price[k], exp_qty[k]));
      check(got_status == exp_status,
            $sformatf("%s: status %s, expected %s", o, st_name(got_status), st_name(exp_status)));
      check(bid_valid == (m_best(BUY)  != -1) && (m_best(BUY)  == -1 || best_bid == m_best(BUY)),
            $sformatf("%s: after the order best bid = %0d (valid %0b), expected %0d", o, best_bid, bid_valid, m_best(BUY)));
      check(ask_valid == (m_best(SELL) != -1) && (m_best(SELL) == -1 || best_ask == m_best(SELL)),
            $sformatf("%s: after the order best ask = %0d (valid %0b), expected %0d", o, best_ask, ask_valid, m_best(SELL)));
    end
  endtask

  // Hand-written check, independent of the model (in case the model and the DUT share a mistake).
  task automatic expect_trade(input string tag, input int k, input int b, input int s, input int p, input int q);
    check(got_n > k && got_buy[k] == b && got_sell[k] == s && got_price[k] == p && got_qty[k] == q,
          $sformatf("%s: trade %0d should be buy=%0d sell=%0d price=%0d qty=%0d", tag, k, b, s, p, q));
  endtask

  task automatic do_reset();
    rst = 1;
    repeat (3) @(posedge clk);
    @(negedge clk) rst = 0;
    m_reset();
  endtask

  // ---------------- the tests ----------------
  initial begin
    int id;
    $timeformat(-9, 0, " ns", 0);
    in_valid = 0; in_id = 0; in_side = 0; in_price = 0; in_qty = 0;

    // D1: rest on an empty book
    do_reset();
    send_order("D1 rest", 1, BUY, 5, 10);
    check(got_status == ACK_RESTED && got_n == 0, "D1: BUY on an empty book should rest with no trades");
    $display("D1 rest on empty book ........ done");

    // D2: simple cross (the Day 1 tb_ref example). Trade price = resting price (rule 3).
    do_reset();
    send_order("D2 cross", 1, BUY, 10, 5);
    send_order("D2 cross", 2, SELL, 9, 8);
    expect_trade("D2", 0, 1, 2, 10, 5);
    check(got_status == ACK_RESTED, "D2: SELL 8 fills 5, so 3 should rest");
    $display("D2 simple cross .............. done");

    // D3: exact fill -> FILLED, resting order removed
    do_reset();
    send_order("D3 exact", 1, SELL, 7, 4);
    send_order("D3 exact", 2, BUY, 7, 4);
    expect_trade("D3", 0, 2, 1, 7, 4);
    check(got_status == ACK_FILLED && !ask_valid, "D3: exact fill should be FILLED and empty the asks");
    $display("D3 exact fill ................ done");

    // D4: partial fill of the RESTING order (dec path), resting order keeps the rest
    do_reset();
    send_order("D4 partial", 1, SELL, 7, 10);
    send_order("D4 partial", 2, BUY, 7, 3);
    expect_trade("D4", 0, 2, 1, 7, 3);
    send_order("D4 partial", 3, BUY, 7, 7);
    expect_trade("D4", 0, 3, 1, 7, 7);
    check(!ask_valid, "D4: 3 + 7 = 10, so the ask should be gone");
    $display("D4 partial fill .............. done");

    // D5: time priority at one price (rule 2)
    do_reset();
    send_order("D5 time", 1, BUY, 10, 3);
    send_order("D5 time", 2, BUY, 10, 3);
    send_order("D5 time", 3, SELL, 10, 4);
    expect_trade("D5", 0, 1, 3, 10, 3);
    expect_trade("D5", 1, 2, 3, 10, 1);
    $display("D5 time priority ............. done");

    // D6: BUY sweeps 2 levels then rests (test_sweep_levels from Day 1)
    do_reset();
    send_order("D6 sweep", 1, SELL, 5, 2);
    send_order("D6 sweep", 2, SELL, 6, 2);
    send_order("D6 sweep", 3, SELL, 7, 2);
    send_order("D6 sweep", 4, BUY, 6, 10);
    expect_trade("D6", 0, 4, 1, 5, 2);
    expect_trade("D6", 1, 4, 2, 6, 2);
    check(got_n == 2 && got_status == ACK_RESTED && best_bid == 6 && best_ask == 7,
          "D6: 2 trades, 6 left rests at bid 6, best ask stays 7");
    $display("D6 buy sweeps levels ......... done");

    // D7: SELL sweeps from the HIGHEST bid down (rule 1, other direction)
    do_reset();
    send_order("D7 sell sweep", 1, BUY, 3, 1);
    send_order("D7 sell sweep", 2, BUY, 9, 1);
    send_order("D7 sell sweep", 3, BUY, 6, 1);
    send_order("D7 sell sweep", 4, SELL, 4, 5);
    expect_trade("D7", 0, 2, 4, 9, 1);
    expect_trade("D7", 1, 3, 4, 6, 1);
    check(got_n == 2 && got_status == ACK_RESTED && best_bid == 3 && best_ask == 4,
          "D7: hits 9 then 6, stops at 3 (below limit 4), 3 left rests at ask 4");
    $display("D7 sell sweeps levels ........ done");

    // D8: full level -> REJECT_FULL (rule 5), no trades
    do_reset();
    for (int i = 1; i <= 4; i++) send_order("D8 full", i, BUY, 3, 1);
    send_order("D8 full", 5, BUY, 3, 1);
    check(got_status == REJECT_FULL && got_n == 0, "D8: 5th BUY at a full level should be REJECT_FULL");
    $display("D8 full level reject ......... done");

    // D9: back-pressure. trade_ready is randomly low; the trades must not change or repeat.
    do_reset();
    bp_mode = 1;
    send_order("D9 backpressure", 1, SELL, 5, 2);
    send_order("D9 backpressure", 2, SELL, 6, 2);
    send_order("D9 backpressure", 3, SELL, 7, 2);
    send_order("D9 backpressure", 4, BUY, 7, 6);
    check(got_n == 3 && got_status == ACK_FILLED, "D9: 3 trades and FILLED even with back-pressure");
    bp_mode = 0;
    $display("D9 back-pressure ............. done");

    // R1 / R2: random orders vs the model (prices 4..11 so books cross often)
    // R1 = trade_ready always 1, R2 = random back-pressure
    for (int phase = 1; phase <= 2; phase++) begin
      do_reset();
      bp_mode = phase - 1;   // R1 no back-pressure, R2 random back-pressure
      total_trades = 0; total_cycles = 0; orders = 0;
      for (int k = 0; k < 3; k++) n_status[k] = 0;
      id = 1;
      for (int n = 0; n < 2000 && errors <= 20 && !stuck; n++) begin
        int q;
        q = ($urandom_range(9, 0) == 0) ? $urandom_range(60, 20) : $urandom_range(8, 1);   // 10% "whales"
        send_order($sformatf("R%0d", phase), id, $urandom_range(1, 0), $urandom_range(11, 4), q);
        id = (id == 255) ? 1 : id + 1;
      end
      $display("R%0d random (%0d orders) ...... done: %0d trades, %0d filled / %0d rested / %0d rejected, avg %0.2f cycles/order",
               phase, orders, total_trades, n_status[ACK_FILLED], n_status[ACK_RESTED], n_status[REJECT_FULL],
               orders ? real'(total_cycles) / orders : 0.0);
    end
    bp_mode = 0;

    $display("--------------------------------------------");
    if (stuck)       $display("Stopped early: the FSM got stuck (see the FAIL line).");
    if (errors > 20) $display("Stopped early: too many failures.");
    if (errors == 0) $display("TB_ENGINE PASSED (%0d checks)", checks);
    else             $display("TB_ENGINE FAILED: %0d of %0d checks failed", errors, checks);
    $finish;
  end
endmodule
