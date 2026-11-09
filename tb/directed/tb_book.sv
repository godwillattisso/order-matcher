// tb_book.sv : Day 2 directed + random test for book_side and best_price
// GIVEN FILE: you don't need to edit it. Read it to see how your RTL is used.
//
//   tasks drive ports ──> [ bids: book_side ] ──occ──┐
//                         [ asks: book_side ] ──occ──┼─> [ best_price ] ──> best bid / ask
//                                                    │
//   same ops ──> model arrays in this file ──────────┴─> compare ──> PASS / FAIL
module tb_book;
  localparam int BUY = 0, SELL = 1;

  // ---------------- clock and reset ----------------
  logic clk = 1'b0;
  always #5 clk = ~clk;          // 100 MHz, same as the Basys3 clock
  logic rst;

  // ---------------- signals for each side (index 0 = bids, 1 = asks) ----------------
  logic [3:0]  sel   [2];
  logic        push  [2], pop [2], dec [2];
  logic [7:0]  pid   [2], pqty[2], dqty[2];
  logic [7:0]  hid   [2], hqty[2];
  logic [2:0]  cnt   [2];
  logic [15:0] occ   [2];

  logic       bid_valid, ask_valid;
  logic [3:0] best_bid, best_ask;

  book_side u_bids (.clk, .rst, .sel_price(sel[0]), .push_en(push[0]), .push_id(pid[0]),
                    .push_qty(pqty[0]), .pop_en(pop[0]), .dec_en(dec[0]), .dec_qty(dqty[0]),
                    .head_id(hid[0]), .head_qty(hqty[0]), .sel_count(cnt[0]), .occ(occ[0]));
  book_side u_asks (.clk, .rst, .sel_price(sel[1]), .push_en(push[1]), .push_id(pid[1]),
                    .push_qty(pqty[1]), .pop_en(pop[1]), .dec_en(dec[1]), .dec_qty(dqty[1]),
                    .head_id(hid[1]), .head_qty(hqty[1]), .sel_count(cnt[1]), .occ(occ[1]));
  best_price u_best (.bid_occ(occ[0]), .ask_occ(occ[1]), .bid_valid, .ask_valid,
                     .best_bid, .best_ask);

  // ---------------- model: what the book SHOULD hold ----------------
  logic [7:0] m_id  [2][16][4];
  logic [7:0] m_qty [2][16][4];
  int         m_cnt [2][16];

  int errors = 0;
  int checks = 0;

  task automatic check(input bit ok, input string what);
    checks++;
    if (!ok) begin
      errors++;
      $display("FAIL #%0d at %0t ns: %s", errors, $time, what);
    end
  endtask

  // ---------------- driving tasks (change inputs on the falling edge) ----------------
  task automatic do_push(input int side, input int price, input int id, input int qty);
    @(negedge clk);
    sel[side] = price; pid[side] = id; pqty[side] = qty; push[side] = 1;
    @(negedge clk);
    push[side] = 0;
    if (m_cnt[side][price] < 4) begin
      m_id [side][price][m_cnt[side][price]] = id;
      m_qty[side][price][m_cnt[side][price]] = qty;
      m_cnt[side][price]++;
    end
  endtask

  task automatic do_pop(input int side, input int price);
    @(negedge clk);
    sel[side] = price; pop[side] = 1;
    @(negedge clk);
    pop[side] = 0;
    if (m_cnt[side][price] > 0) begin
      for (int i = 0; i < 3; i++) begin
        m_id [side][price][i] = m_id [side][price][i+1];
        m_qty[side][price][i] = m_qty[side][price][i+1];
      end
      m_cnt[side][price]--;
    end
  endtask

  task automatic do_dec(input int side, input int price, input int amount);
    @(negedge clk);
    sel[side] = price; dqty[side] = amount; dec[side] = 1;
    @(negedge clk);
    dec[side] = 0;
    if (m_cnt[side][price] > 0) m_qty[side][price][0] -= amount;
  endtask

  // Look at one level: point sel at it and let the combinational outputs settle.
  task automatic peek(input int side, input int price);
    sel[side] = price;
    #1;
  endtask

  // ---------------- checking tasks ----------------
  task automatic check_level(input int side, input int price, input string tag);
    string s;
    peek(side, price);
    s = (side == BUY) ? "bid" : "ask";
    check(cnt[side] == m_cnt[side][price],
          $sformatf("%s %s level %0d: count %0d, expected %0d", tag, s, price, cnt[side], m_cnt[side][price]));
    check(occ[side][price] == (m_cnt[side][price] != 0),
          $sformatf("%s %s occ[%0d] = %0b, expected %0b", tag, s, price, occ[side][price], m_cnt[side][price] != 0));
    if (m_cnt[side][price] > 0) begin
      check(hid[side] == m_id[side][price][0],
            $sformatf("%s %s level %0d: head id %0d, expected %0d", tag, s, price, hid[side], m_id[side][price][0]));
      check(hqty[side] == m_qty[side][price][0],
            $sformatf("%s %s level %0d: head qty %0d, expected %0d", tag, s, price, hqty[side], m_qty[side][price][0]));
    end
  endtask

  task automatic check_best(input string tag);
    int mb, ma;
    mb = -1; ma = -1;
    for (int p = 0; p < 16; p++)   if (m_cnt[BUY][p]  > 0) mb = p;   // highest bid
    for (int p = 15; p >= 0; p--)  if (m_cnt[SELL][p] > 0) ma = p;   // lowest ask
    #1;
    check(bid_valid == (mb != -1), $sformatf("%s bid_valid = %0b, expected %0b", tag, bid_valid, mb != -1));
    check(ask_valid == (ma != -1), $sformatf("%s ask_valid = %0b, expected %0b", tag, ask_valid, ma != -1));
    if (mb != -1) check(best_bid == mb, $sformatf("%s best_bid = %0d, expected %0d", tag, best_bid, mb));
    if (ma != -1) check(best_ask == ma, $sformatf("%s best_ask = %0d, expected %0d", tag, best_ask, ma));
  endtask

  task automatic check_all(input string tag);
    for (int s = 0; s < 2; s++)
      for (int p = 0; p < 16; p++)
        check_level(s, p, tag);
    check_best(tag);
  endtask

  // ---------------- the tests ----------------
  initial begin
    for (int s = 0; s < 2; s++) begin
      sel[s] = 0; push[s] = 0; pop[s] = 0; dec[s] = 0;
      pid[s] = 0; pqty[s] = 0; dqty[s] = 0;
      for (int p = 0; p < 16; p++) m_cnt[s][p] = 0;
    end

    // T1: reset -> both sides empty
    rst = 1;
    repeat (3) @(posedge clk);
    @(negedge clk) rst = 0;
    check_all("T1 reset");
    $display("T1 reset ............ done");

    // T2: best bid = HIGHEST bid, best ask = LOWEST ask (bids 4,8 / asks 9,12)
    do_push(BUY, 4, 1, 10);
    do_push(BUY, 8, 2, 20);
    do_push(SELL, 12, 3, 30);
    do_push(SELL, 9, 4, 40);
    check_all("T2 best price");
    check(best_bid == 8 && best_ask == 9, "T2 expected best bid 8, best ask 9");
    $display("T2 best price ....... done");

    // T3: time priority -> oldest stays at the front of its level
    do_push(SELL, 9, 5, 41);
    do_push(SELL, 9, 6, 42);
    check_all("T3 FIFO order");
    peek(SELL, 9);
    check(hid[SELL] == 4, "T3 head of ask level 9 should be id 4 (the oldest)");
    $display("T3 FIFO order ....... done");

    // T4: fill a level to 4, then a 5th push must be ignored
    do_push(SELL, 9, 7, 43);
    peek(SELL, 9);
    check(cnt[SELL] == 4, "T4 ask level 9 should hold 4 orders");
    do_push(SELL, 9, 8, 44);   // ignored: level is full
    check_all("T4 full level");
    $display("T4 full level ....... done");

    // T5: partial fill -> head qty goes down, order stays
    do_dec(SELL, 9, 15);       // id 4: 40 -> 25
    check_all("T5 partial fill");
    peek(SELL, 9);
    check(hqty[SELL] == 25, "T5 head qty should be 40 - 15 = 25");
    $display("T5 partial fill ..... done");

    // T6: pops come out in arrival order: 4, 5, 6, 7
    for (int k = 0; k < 4; k++) begin
      peek(SELL, 9);
      check(hid[SELL] == 4 + k, $sformatf("T6 pop %0d: head id %0d, expected %0d", k, hid[SELL], 4 + k));
      do_pop(SELL, 9);
    end
    check_all("T6 drain level");
    $display("T6 drain level ...... done");

    // T7: emptying the best level moves the best price (this is a "sweep")
    check(best_ask == 12, "T7 level 9 empty -> best ask should move to 12");
    do_pop(BUY, 8);
    check_all("T7 sweep");
    check(best_bid == 4, "T7 level 8 empty -> best bid should move to 4");
    $display("T7 sweep ............ done");

    // T8: edge prices 0 and 15 (first and last bit of the encoders)
    do_push(BUY, 15, 9, 1);
    do_push(SELL, 0, 10, 1);
    check_all("T8 edge prices");
    check(best_bid == 15 && best_ask == 0, "T8 expected best bid 15, best ask 0");
    $display("T8 edge prices ...... done");

    // T9: reset in the middle clears everything
    @(negedge clk) rst = 1;
    @(negedge clk) rst = 0;
    for (int s = 0; s < 2; s++) for (int p = 0; p < 16; p++) m_cnt[s][p] = 0;
    check_all("T9 mid reset");
    $display("T9 mid reset ........ done");

    // T10: 3000 random legal operations, everything checked after each one
    for (int n = 0; n < 3000 && errors <= 20; n++) begin
      int side, price, op;
      side  = $urandom_range(1, 0);
      price = $urandom_range(15, 0);
      op    = $urandom_range(2, 0);
      if (m_cnt[side][price] == 0) op = 0;                       // empty: can only push
      if (op == 0 && m_cnt[side][price] == 4) op = 1;            // full: pop instead
      if (op == 2 && m_qty[side][price][0] < 2) op = 1;          // can't dec a qty-1 order
      case (op)
        0: do_push(side, price, $urandom_range(255, 0), $urandom_range(255, 1));
        1: do_pop(side, price);
        2: do_dec(side, price, $urandom_range(m_qty[side][price][0] - 1, 1));
      endcase
      check_all($sformatf("T10 random op %0d", n));
    end
    if (errors > 20) $display("Too many failures, stopped early.");
    $display("T10 random .......... done");

    $display("--------------------------------------------");
    if (errors == 0) $display("TB_BOOK PASSED (%0d checks)", checks);
    else             $display("TB_BOOK FAILED: %0d of %0d checks failed", errors, checks);
    $finish;
  end
endmodule
