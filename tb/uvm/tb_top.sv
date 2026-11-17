// tb_top.sv : the top of the UVM testbench. Makes the clock and reset, connects the
// DUT to the interface, hands the interface to UVM, and starts the test.
module tb_top;
  timeunit 1ns; timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import om_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;              // 100 MHz

  order_if vif (clk);

  match_engine dut (
    .clk,            .rst(vif.rst),
    .in_valid(vif.in_valid),       .in_ready(vif.in_ready),
    .in_id(vif.in_id),             .in_side(vif.in_side),
    .in_price(vif.in_price),       .in_qty(vif.in_qty),
    .trade_valid(vif.trade_valid), .trade_ready(vif.trade_ready),
    .trade_buy_id(vif.trade_buy_id), .trade_sell_id(vif.trade_sell_id),
    .trade_price(vif.trade_price), .trade_qty(vif.trade_qty),
    .done_valid(vif.done_valid),   .done_status(vif.done_status),
    .bid_valid(vif.bid_valid),     .ask_valid(vif.ask_valid),
    .best_bid(vif.best_bid),       .best_ask(vif.best_ask));

  // Attach the assertion modules (om_sva.sv) INSIDE the RTL, without editing the RTL.
  // .* connects each assertion port to the signal with the same name inside that module.
  bind book_side    book_sva   u_book_sva   (.*);
  bind match_engine engine_sva u_engine_sva (.*);

  initial begin
    vif.rst = 1;
    repeat (3) @(posedge clk);
    @(negedge clk) vif.rst = 0;
  end

  // Read +UVM_TESTNAME here too, so the log shows which test ran. Default: random_mix_test.
  string test_name = "random_mix_test";
  initial begin
    if ($value$plusargs("UVM_TESTNAME=%s", test_name))
      $display("tb_top: running test %s", test_name);
    uvm_config_db#(virtual order_if)::set(null, "*", "vif", vif);
    run_test(test_name);
  end
endmodule
