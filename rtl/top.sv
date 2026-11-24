// top.sv : the whole design on the Basys3 board.
//
//  PC (USB serial) ──RsRx──► uart_rx ──bytes──► order_rx ──order──► match_engine
//                                                                    │ trades  │ done
//  PC ◄──RsTx── uart_tx ◄──bytes── report_tx ◄───────────────────────┘         │
//                                       ▲─────────────────────────────────────┘
//  match_engine ── best bid/ask ──► seg7_display ──► 7-segment digits
//  counters ──► LEDs: led[7:0] = trades so far, led[15:8] = orders so far (both wrap at 256)
//
// Clock: the board's 100 MHz oscillator goes into an MMCM (a clock generator inside the FPGA) that
// makes a 50 MHz clock for the whole design. At 100 MHz the engine failed timing (WNS -2.262 ns):
// its longest path (book count -> best price -> FSM -> book update enable, 12 logic levels, fanout
// 120) needs ~12.3 ns, so the design can run at up to ~81 MHz. 50 MHz gives a large safety margin.
// The simulation testbenches don't use the MMCM (see `ifdef SYNTHESIS below); they drive the clock directly.
//
// Reset: the centre button (btnC), plus an automatic reset for 16 cycles after the clock is stable
// (power-on reset), so the board starts clean without pressing anything.

module top #(
  parameter int CLKS_PER_BIT = 434,         // 50 MHz / 115200 baud
  parameter int TRADE_FLASH  = 25_000_000   // decimal points light for 0.5 s after each trade (50 MHz)
) (
  input  logic        clk_100,              // 100 MHz oscillator (pin W5)
  input  logic        btnC,                 // centre button = reset
  input  logic        RsRx,                 // serial from the PC
  output logic        RsTx,                 // serial to the PC
  output logic [6:0]  seg,
  output logic        dp,
  output logic [3:0]  an,
  output logic [15:0] led
);

  // ---------------- clock: 100 MHz in -> 50 MHz for the design ----------------
  logic clk;              // the design clock (50 MHz on the board)
  logic mmcm_locked;      // 1 once the MMCM's output clock is stable
`ifdef SYNTHESIS
  // MMCM: VCO = 100 MHz x 10 = 1000 MHz (legal range 600-1200), output = 1000 / 20 = 50 MHz.
  logic clk_fb, clk_50_unbuf;
  MMCME2_BASE #(
    .CLKIN1_PERIOD   (10.0),
    .CLKFBOUT_MULT_F (10.0),
    .DIVCLK_DIVIDE   (1),
    .CLKOUT0_DIVIDE_F(20.0)
  ) u_mmcm (
    .CLKIN1(clk_100), .CLKFBIN(clk_fb), .CLKFBOUT(clk_fb),
    .CLKOUT0(clk_50_unbuf), .LOCKED(mmcm_locked),
    .RST(1'b0), .PWRDWN(1'b0),
    .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
  );
  BUFG u_bufg (.I(clk_50_unbuf), .O(clk));   // global clock buffer: reaches every flip-flop with low skew
`else
  // Simulation: no MMCM model needed, the testbench clock is the design clock.
  assign clk         = clk_100;
  assign mmcm_locked = 1'b1;
`endif

  // ---------------- reset ----------------
  logic [1:0] btn_sync = '0;                 // the button is asynchronous: synchronize it
  logic [4:0] por_cnt  = '0;                 // counts 0..16 after configuration
  logic       rst;
  always_ff @(posedge clk) begin
    btn_sync <= {btn_sync[0], btnC};
    if (!mmcm_locked)    por_cnt <= '0;              // hold reset until the clock is stable
    else if (!por_cnt[4]) por_cnt <= por_cnt + 1'b1;
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

  // Trade indicator: every trade lights the decimal points for TRADE_FLASH cycles.
  // dp is shared by all 4 digits (like seg), so all 4 dots light. Active-low: 0 = on.
  logic [$clog2(TRADE_FLASH+1)-1:0] flash_cnt;
  always_ff @(posedge clk) begin
    if (rst)                             flash_cnt <= '0;
    else if (trade_valid && trade_ready) flash_cnt <= TRADE_FLASH;
    else if (flash_cnt != 0)             flash_cnt <= flash_cnt - 1'b1;
  end
  assign dp = (flash_cnt == 0);

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
