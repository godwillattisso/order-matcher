// top.sv : the whole design on the Basys3 board.  (GIVEN)
//
//  PC (USB serial) ──RsRx──► uart_rx ──bytes──► order_rx ──order──► match_engine
//                                                                    │ trades  │ done
//  PC ◄──RsTx── uart_tx ◄──bytes── report_tx ◄───────────────────────┘         │
//                                       ▲─────────────────────────────────────┘
//  match_engine ── best bid/ask ──► seg7_display ──► 7-segment digits
//  counters ──► LEDs: led[7:0] = trades so far, led[15:8] = orders so far (both wrap at 256)
//
// Reset: the centre button (btnC), plus an automatic reset for the first 16 cycles after the
// bitstream loads (power-on reset), so the board starts clean without pressing anything.

module top #(
  parameter int CLKS_PER_BIT = 868          // 100 MHz / 115200 baud
) (
  input  logic        clk,                  // 100 MHz oscillator (pin W5)
  input  logic        btnC,                 // centre button = reset
  input  logic        RsRx,                 // serial from the PC
  output logic        RsTx,                 // serial to the PC
  output logic [6:0]  seg,
  output logic        dp,
  output logic [3:0]  an,
  output logic [15:0] led
);

  // ---------------- reset ----------------
  logic [1:0] btn_sync = '0;                 // the button is asynchronous: synchronize it
  logic [4:0] por_cnt  = '0;                 // counts 0..16 after configuration
  logic       rst;
  always_ff @(posedge clk) begin
    btn_sync <= {btn_sync[0], btnC};
    if (!por_cnt[4]) por_cnt <= por_cnt + 1'b1;
    rst <= !por_cnt[4] || btn_sync[1];
  end

  // ---------------- UART in → order ----------------
  logic [7:0] rx_data;
  logic       rx_valid;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
    .clk, .rst, .rx(RsRx), .data(rx_data), .valid(rx_valid));

  logic       ord_valid, ord_ready, ord_side;
  logic [7:0] ord_id, ord_qty;
  logic [3:0] ord_price;
  order_rx u_ord (
    .clk, .rst, .byte_data(rx_data), .byte_valid(rx_valid),
    .out_valid(ord_valid), .out_ready(ord_ready),
    .out_id(ord_id), .out_side(ord_side), .out_price(ord_price), .out_qty(ord_qty));

  // ---------------- engine ----------------
  logic       in_valid, in_ready;
  logic       trade_valid, trade_ready;
  logic [7:0] trade_buy_id, trade_sell_id, trade_qty;
  logic [3:0] trade_price;
  logic       done_valid;
  logic [1:0] done_status;
  logic       bid_valid, ask_valid;
  logic [3:0] best_bid, best_ask;
  logic       rpt_idle;

  // Only start a new order when the previous order's messages are all queued (see report_tx).
  assign in_valid  = ord_valid && rpt_idle;
  assign ord_ready = in_ready  && rpt_idle;

  match_engine u_eng (
    .clk, .rst,
    .in_valid, .in_ready, .in_id(ord_id), .in_side(ord_side), .in_price(ord_price), .in_qty(ord_qty),
    .trade_valid, .trade_ready, .trade_buy_id, .trade_sell_id, .trade_price, .trade_qty,
    .done_valid, .done_status,
    .bid_valid, .ask_valid, .best_bid, .best_ask);

  // ---------------- performance counter ----------------
  // Engine cycles per order, from the cycle the order is accepted to the done pulse (both counted),
  // NOT counting cycles stalled by back-pressure (trade waiting, trade_ready = 0). This is the
  // number the simulation measured (rest = 4, +2 per fill), now measured on the real chip.
  wire        in_fire = in_valid && in_ready;
  wire        stalled = trade_valid && !trade_ready;
  logic [7:0] cyc, cur_id;
  always_ff @(posedge clk) begin
    if (rst)          cyc <= '0;
    else if (in_fire) begin
      cyc    <= 8'd1;
      cur_id <= ord_id;
    end else if (!stalled && cyc != 8'hFF) cyc <= cyc + 1'b1;   // saturate at 255
  end

  // ---------------- engine → UART out ----------------
  logic [7:0] tx_data;
  logic       tx_valid, tx_ready;
  report_tx u_rpt (
    .clk, .rst,
    .trade_valid, .trade_ready, .trade_buy_id, .trade_sell_id, .trade_price, .trade_qty,
    .done_valid, .done_status, .done_id(cur_id), .done_cycles(cyc + 8'd1),
    .tx_data, .tx_valid, .tx_ready, .idle(rpt_idle));

  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
    .clk, .rst, .data(tx_data), .valid(tx_valid), .ready(tx_ready), .tx(RsTx));

  // ---------------- display + LEDs ----------------
  seg7_display u_seg (.clk, .bid_valid, .best_bid, .ask_valid, .best_ask, .seg, .an);
  assign dp = 1'b1;                          // decimal points off

  logic [7:0] n_trades, n_orders;
  always_ff @(posedge clk) begin
    if (rst) begin
      n_trades <= '0;
      n_orders <= '0;
    end else begin
      if (trade_valid && trade_ready) n_trades <= n_trades + 1'b1;
      if (in_fire)                    n_orders <= n_orders + 1'b1;
    end
  end
  assign led = {n_orders, n_trades};

endmodule
