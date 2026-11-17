// order_tests_more.svh : one test per market scenario, plus one that runs them all.
// Run one with:  scripts\run_uvm.bat <test_name> <seed> [n_orders] [bp_percent]

// Helper used by the tests below: run one market_seq with the given knobs.
class market_test_base extends base_test;
  `uvm_component_utils(market_test_base)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_market(int n, int p_lo, int p_hi, int q_lo, int q_hi, int whale, int buy);
    market_seq seq = market_seq::type_id::create("mkt");
    seq.n_orders  = n;
    seq.price_lo  = p_lo;  seq.price_hi = p_hi;
    seq.qty_lo    = q_lo;  seq.qty_hi   = q_hi;
    seq.whale_pct = whale; seq.buy_pct  = buy;
    seq.start(env.agent.sqr);
  endtask

  task run_fill_levels(int rounds);
    fill_level_seq seq = fill_level_seq::type_id::create("fill");
    seq.n_rounds = rounds;
    seq.start(env.agent.sqr);
  endtask
endclass

// Wide price range: books rarely cross, most orders rest.
class calm_market_test extends market_test_base;
  `uvm_component_utils(calm_market_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();  run_market(n_orders, 0, 15, 1, 8, 0, 50);  endtask
endclass

// Narrow price range, medium sizes: almost every order crosses.
class frantic_market_test extends market_test_base;
  `uvm_component_utils(frantic_market_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();  run_market(n_orders, 7, 8, 1, 19, 10, 50);  endtask
endclass

// Half the orders are whales that sweep several levels.
class whale_test extends market_test_base;
  `uvm_component_utils(whale_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();  run_market(n_orders, 4, 11, 1, 8, 50, 50);  endtask
endclass

// All BUYs, then all SELLs: the opposite side starts empty, then gets swept.
class one_sided_test extends market_test_base;
  `uvm_component_utils(one_sided_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();
    run_market(n_orders / 2, 4, 11, 1, 8, 0, 100);
    run_market(n_orders / 2, 4, 11, 1, 8, 20, 0);
  endtask
endclass

// Full levels and rejects, mixed with normal traffic.
class fill_level_test extends market_test_base;
  `uvm_component_utils(fill_level_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();
    run_fill_levels(20);
    run_market(n_orders / 2, 4, 11, 1, 8, 10, 50);
    run_fill_levels(20);
  endtask
endclass

// Every scenario back to back in ONE run, so one coverage number covers everything.
class all_scenarios_test extends market_test_base;
  `uvm_component_utils(all_scenarios_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  // Default to 20% back-pressure so the "stalled" coverage bin is reachable (+BP= overrides it).
  function void build_phase(uvm_phase phase);
    bp_pct = 20;
    super.build_phase(phase);
  endfunction
  task run_stimulus();
    int n = n_orders / 5;
    run_market(n / 2, 8, 15, 1, 8, 0, 0);      // empty book: a "ladder" of small SELLs at 8..15
    run_market(n / 2, 15, 15, 1, 8, 100, 100); // BUY whales at 15 sweep up the ladder (4+ levels)
    run_market(n, 4, 11, 1, 8, 0, 100);        // one-sided: BUYs...
    run_market(n, 4, 11, 1, 8, 20, 0);         //            ...then SELLs sweep them
    run_market(n, 0, 15, 1, 8, 0, 50);         // calm
    run_market(n, 7, 8, 1, 19, 10, 50);        // frantic, medium sizes
    run_fill_levels(20);                       // full levels, rejects
  endtask
endclass
