// report_tx.sv : turns trades and order results into UART bytes for the PC.  (GIVEN)
//
// Messages to the PC:
//   trade : 'T' (0x54) | buy_id | sell_id | price | qty          (5 bytes)
//   done  : 'D' (0x44) | id     | status  | cycles               (4 bytes)
//           status 0 RESTED, 1 FILLED, 2 REJECTED. cycles = engine cycles for this order.
//
// Back-pressure in real life: one byte takes ~87 us on the wire = ~8,700 engine cycles.
// While a message is being sent, trade_ready = 0, so the engine WAITS in FILL. This is the
// valid/ready back-pressure you tested in simulation, now caused by a slow UART.
//
// done_valid has no ready (a 1-cycle pulse), so this block saves it in done_pend and sends it
// after the current message. idle = 0 while anything is pending; top only lets the engine take
// the next order when idle = 1, so a second done can never arrive before the first is sent.

module report_tx (
  input  logic       clk,
  input  logic       rst,
  // trades from the engine
  input  logic       trade_valid,
  output logic       trade_ready,
  input  logic [7:0] trade_buy_id,
  input  logic [7:0] trade_sell_id,
  input  logic [3:0] trade_price,
  input  logic [7:0] trade_qty,
  // order result
  input  logic       done_valid,
  input  logic [1:0] done_status,
  input  logic [7:0] done_id,       // id of the order that just finished (latched in top)
  input  logic [7:0] done_cycles,   // engine cycles for that order (counted in top)
  // to uart_tx
  output logic [7:0] tx_data,
  output logic       tx_valid,
  input  logic       tx_ready,
  // nothing waiting or being sent
  output logic       idle
);

  logic [7:0] msg [5];     // the message being sent
  logic [2:0] len, idx;    // its length, and the byte being sent now
  logic       busy;        // a message is being sent
  logic       done_pend;   // a done result is waiting to be sent
  logic [7:0] pend_id, pend_status, pend_cycles;

  assign trade_ready = !busy && !done_pend;
  assign tx_valid    = busy;
  assign tx_data     = msg[idx];
  assign idle        = !busy && !done_pend && !done_valid;

  always_ff @(posedge clk) begin
    if (rst) begin
      busy      <= 1'b0;
      done_pend <= 1'b0;
      idx       <= '0;
      len       <= '0;
    end else begin
      if (busy) begin
        if (tx_valid && tx_ready) begin                 // uart_tx took msg[idx]
          if (idx == len - 1) busy <= 1'b0;
          else                idx  <= idx + 1'b1;
        end
      end else if (done_pend) begin                     // send the saved result
        msg[0] <= 8'h44;  msg[1] <= pend_id;  msg[2] <= pend_status;  msg[3] <= pend_cycles;
        len <= 3'd4;  idx <= '0;  busy <= 1'b1;
        done_pend <= 1'b0;
      end else if (trade_valid) begin                   // trade_ready is 1 here: take the trade
        msg[0] <= 8'h54;  msg[1] <= trade_buy_id;  msg[2] <= trade_sell_id;
        msg[3] <= {4'd0, trade_price};  msg[4] <= trade_qty;
        len <= 3'd5;  idx <= '0;  busy <= 1'b1;
      end

      if (done_valid) begin                             // save the 1-cycle pulse
        done_pend   <= 1'b1;
        pend_id     <= done_id;
        pend_status <= {6'd0, done_status};
        pend_cycles <= done_cycles;
      end
    end
  end

endmodule
