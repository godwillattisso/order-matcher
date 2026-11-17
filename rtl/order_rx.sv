// order_rx.sv : turns UART bytes from the PC into one order for the engine.  (GIVEN)
//
// Packet from the PC, 5 bytes:   0xA5 | id | side (0 BUY, 1 SELL) | price (0-15) | qty (1-255)
//   0xA5 is a "header": a byte we wait for so we know where a packet starts.
//
// After the 5th byte the order is held on out_* with out_valid = 1 until the engine takes it
// (out_valid && out_ready). Bytes that arrive while an order is waiting are dropped; the PC
// script sends one order and waits for its reply, so that never happens in normal use.
//
// Assumption: the PC only sends legal values (the script checks them). Here side and price are
// cut to their bit widths; qty 0 would be passed through, so the script never sends it.

module order_rx (
  input  logic       clk,
  input  logic       rst,
  input  logic [7:0] byte_data,   // from uart_rx
  input  logic       byte_valid,
  output logic       out_valid,   // to the engine (through top)
  input  logic       out_ready,
  output logic [7:0] out_id,
  output logic       out_side,
  output logic [3:0] out_price,
  output logic [7:0] out_qty
);

  localparam logic [7:0] HEADER = 8'hA5;

  logic [2:0] idx;        // 0 = waiting for the header, 1..4 = next payload byte
  logic [7:0] b [4];      // payload: id, side, price, qty

  always_ff @(posedge clk) begin
    if (rst) begin
      idx       <= '0;
      out_valid <= 1'b0;
    end else begin
      if (out_valid && out_ready) out_valid <= 1'b0;           // engine took the order

      if (byte_valid && !out_valid) begin
        if (idx == 0) begin
          if (byte_data == HEADER) idx <= 3'd1;               // anything else: keep waiting
        end else begin
          b[idx - 1] <= byte_data;
          if (idx == 3'd4) begin
            idx       <= '0;
            out_valid <= 1'b1;                                // 5th byte done: order ready
          end else idx <= idx + 1'b1;
        end
      end
    end
  end

  assign out_id    = b[0];
  assign out_side  = b[1][0];
  assign out_price = b[2][3:0];
  assign out_qty   = b[3];

endmodule
