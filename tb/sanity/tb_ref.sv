// tb_ref.sv - Check 3: calls the real C++ order book model from SystemVerilog.
// This is the exact connection the UVM scoreboard will use on Day 4.
`timescale 1ns/1ps
module tb_ref;
  import "DPI-C" function void ref_reset();
  import "DPI-C" function int  ref_submit(input int id, input int side, input int price, input int qty);
  import "DPI-C" function void ref_get_trade(input int idx, output int buy_id, output int sell_id,
                                             output int price, output int qty);
  import "DPI-C" function int  ref_status();

  int n, b, s, p, q;

  initial begin
    ref_reset();

    n = ref_submit(1, 0, 10, 5);   // BUY 5 @ 10 -> nothing to match, rests
    $display("order 1 (BUY 5 @ 10):  %0d trades, status %0d (0 = rested)", n, ref_status());

    n = ref_submit(2, 1, 9, 8);    // SELL 8 @ 9 -> trades 5 @ 10, 3 rest at 9
    $display("order 2 (SELL 8 @ 9):  %0d trades, status %0d (0 = rested)", n, ref_status());

    for (int i = 0; i < n; i++) begin
      ref_get_trade(i, b, s, p, q);
      $display("  trade %0d: buy_id=%0d sell_id=%0d price=%0d qty=%0d", i, b, s, p, q);
    end

    if (n == 1 && b == 1 && s == 2 && p == 10 && q == 5)
      $display("REF MODEL DPI PASSED");
    else
      $display("REF MODEL DPI FAILED");
    $finish;
  end
endmodule
