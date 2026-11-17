// order_scoreboard.svh : the pass/fail judge.
//   During the run : collect every order_result from the monitor (what the DUT DID).
//   After the run  : write the orders to orders.txt, run YOUR C++ model on them
//                    (ref_runner.exe), read expected.txt (what it SHOULD do), compare.
class order_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(order_scoreboard)

  uvm_analysis_imp #(order_result, order_scoreboard) imp;   // the monitor connects here

  order_result got[$];                                     // DUT results, in order
  string       ref_exe = "..\\..\\model\\ref_runner.exe";  // override with +REF=<path>

  // Expected results from the C++ model, indexed by order number
  int     exp_status[int];
  int     exp_ntr[int];
  trade_t exp_trades[int][$];

  int n_compared, n_trades, n_mismatch;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction

  // Called by the monitor's ap.write(): just store it.
  function void write(order_result r);
    got.push_back(r);
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if ($value$plusargs("REF=%s", ref_exe)) `uvm_info("SB", {"model: ", ref_exe}, UVM_LOW)
    if (got.size() == 0) begin
      `uvm_error("SB", "No orders were completed: nothing to check")
      return;
    end
    if (!write_orders("orders.txt")) return;
    if (!run_model("orders.txt", "expected.txt")) return;
    if (!read_expected("expected.txt")) return;
    compare_all();
    // A checker that checks nothing must not pass:
    if (n_compared != got.size())
      `uvm_error("SB", $sformatf("compare_all() checked %0d of %0d orders", n_compared, got.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("Compared %0d orders and %0d trades against the C++ model: %0d mismatches",
                              n_compared, n_trades, n_mismatch), UVM_NONE)
  endfunction

  // ---------------- file plumbing (given) ----------------
  function bit write_orders(string fname);
    int fd = $fopen(fname, "w");
    if (fd == 0) begin `uvm_error("SB", {"cannot create ", fname}) return 0; end
    foreach (got[i]) $fdisplay(fd, "%0d %0d %0d %0d", got[i].id, got[i].side, got[i].price, got[i].qty);
    $fclose(fd);
    return 1;
  endfunction

  function bit run_model(string fin, string fout);
    int rc = $system({ref_exe, " ", fin, " ", fout});
    if (rc != 0) begin
      `uvm_error("SB", $sformatf("'%s' returned %0d. Is ref_runner.exe built in model\\?", ref_exe, rc))
      return 0;
    end
    return 1;
  endfunction

  function bit read_expected(string fname);
    int     fd, n, idx, a, b, c;
    string  kind;
    trade_t t;
    fd = $fopen(fname, "r");
    if (fd == 0) begin `uvm_error("SB", {"cannot open ", fname}) return 0; end
    while ($fscanf(fd, "%s", kind) == 1) begin
      if (kind == "S") begin
        n = $fscanf(fd, "%d %d %d", idx, a, b);
        exp_ntr[idx]    = a;
        exp_status[idx] = b;
      end else if (kind == "T") begin
        n = $fscanf(fd, "%d %d %d %d %d", idx, t.buy_id, t.sell_id, t.price, t.qty);
        exp_trades[idx].push_back(t);
      end
    end
    $fclose(fd);
    return 1;
  endfunction

  // ---------------- the comparison ----------------
  
  function void compare_all();
    order_result r;
    trade_t d, e;
    
    // Loop through every order captured by the monitor
    foreach (got[i]) begin
      r = got[i];                                                     // Get the current order
      n_compared++;                                                   // Incremement number of orders compared

      // Check if the C++ model has a result for this order
      if (!exp_status.exists(r.idx)) begin
          mismatch(r, "No expected result from C++ model");
          continue;
      end

      // Check if the C++ model rejected the input as illegal
      if (exp_ntr[r.idx] < 0) begin
          mismatch(r, "C++ model reports illegal order");
          continue;
      end

      //Compare the number of trades
      if (r.trades.size() != exp_ntr[r.idx]) begin
          mismatch(r, $sformatf(
              "DUT made %0d trades, model made %0d",
              r.trades.size(), exp_ntr[r.idx]
          ));
      end

      // Compare each trade's information
      for (int k = 0;
            k < r.trades.size() && k < exp_trades[r.idx].size();
            k++) begin

          d = r.trades[k];
          e = exp_trades[r.idx][k];
          n_trades++;

          if (d.buy_id  != e.buy_id  ||
              d.sell_id != e.sell_id ||
              d.price   != e.price   ||
              d.qty     != e.qty) begin

              mismatch(r, $sformatf(
                  "Trade %0d: DUT=(%0d,%0d,%0d,%0d), C++=(%0d,%0d,%0d,%0d)",
                  k,
                  d.buy_id, d.sell_id, d.price, d.qty,
                  e.buy_id, e.sell_id, e.price, e.qty
              ));
          end
      end

      // Compare the final order status
      if (r.status != exp_status[r.idx]) begin
          mismatch(r, $sformatf(
              "Status: DUT=%0d, C++=%0d",
              r.status, exp_status[r.idx]
          ));
      end
    end
  endfunction


  function void mismatch(order_result r, string what);
    string sd;
    if (r.side) sd = "SELL"; else sd = "BUY";
    n_mismatch++;
    if (n_mismatch <= 10)   // print the first 10 in full; the count covers the rest
      `uvm_error("MISMATCH", $sformatf("order #%0d (id=%0d %s %0d @ %0d): %s",
                 r.idx, r.id, sd, r.qty, r.price, what))
  endfunction
endclass
