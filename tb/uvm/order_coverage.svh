// order_coverage.svh : FUNCTIONAL COVERAGE = "did the tests actually exercise each scenario?"
// The scoreboard says the DUT was right for every order it saw. Coverage says WHICH kinds of
// orders it saw. 100% means every bin below was hit at least once.
class order_coverage extends uvm_subscriber #(order_result);
  `uvm_component_utils(order_coverage)

  virtual order_if vif;

  // values sampled for each finished order
  int side;        // 0 BUY, 1 SELL
  int outcome;     // 0 rested with no trade, 1 traded then rested, 2 filled, 3 rejected
  int n_levels;    // how many different price levels it traded at (0 = none)
  int qty;
  bit opp_empty;   // was the opposite side of the book empty when it arrived?
  bit stalled;     // was trade_ready ever 0 while one of its trades was waiting?

  //per-order flags collected from the pins
  bit cur_opp_empty, cur_stalled;

  covergroup order_cg;
    option.per_instance = 1;
    cp_side: coverpoint side {
      bins buy  = {0};
      bins sell = {1};
    }
    cp_outcome: coverpoint outcome {
      bins rested_no_trade = {0};
      bins partial_rested  = {1};
      bins filled          = {2};
      bins rejected        = {3};
    }
    cx_side_outcome: cross cp_side,  cp_outcome;

    cp_levels: coverpoint n_levels {
      bins zero_levels = {0};
      bins one_level = {1};
      bins two_three = {[2:3]};
      bins four_plus = {[4:16]};
    }
    cp_qty: coverpoint qty {
      bins qty_small = {[1:8]};
      bins qty_medium = {[9:19]};
      bins qty_whale = {[20:255]};
    }

    cp_opp_empty: coverpoint opp_empty{
      bins empty = {1};
      bins not_empty = {0};
    }

    cp_stalled: coverpoint stalled{
      bins stalled = {1};
      bins no_stall = {0};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    order_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual order_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "order_if not found in config_db")
  endfunction

  // Watches the pins for the two things order_result doesn't carry.
  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.rst) continue;
      if (vif.in_valid && vif.in_ready) begin
        cur_opp_empty = vif.in_side ? !vif.bid_valid : !vif.ask_valid;   // BUY looks at asks
        cur_stalled   = 0;
      end
      if (vif.trade_valid && !vif.trade_ready) cur_stalled = 1;
    end
  endtask

  // Called by the monitor for every finished order.
  function void write(order_result t);
    int prices[int];                    // set of distinct trade prices
    side      = t.side;
    qty       = t.qty;
    opp_empty = cur_opp_empty;
    stalled   = cur_stalled;
    foreach (t.trades[k]) prices[t.trades[k].price] = 1;
    n_levels  = prices.num();
    if      (t.status == 2)        outcome = 3;   // REJECT_FULL
    else if (t.status == 1)        outcome = 2;   // FILLED
    else if (t.trades.size() > 0)  outcome = 1;   // RESTED after some trades
    else                           outcome = 0;   // RESTED, no trades
    order_cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("Functional coverage: %0.1f%%", order_cg.get_inst_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf("levels %0.0f%%  qty %0.0f%%  opp_empty %0.0f%%  stalled %0.0f%%  cross %0.0f%%",
      order_cg.cp_levels.get_inst_coverage(), order_cg.cp_qty.get_inst_coverage(),
      order_cg.cp_opp_empty.get_inst_coverage(), order_cg.cp_stalled.get_inst_coverage(),
      order_cg.cx_side_outcome.get_inst_coverage()), UVM_NONE)
  endfunction
endclass
