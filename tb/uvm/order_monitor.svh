// order_monitor.svh : watches the DUT's pins and reports what really happened.
// One order_result per order: the order (seen at the input handshake), every trade
// (seen at the trade handshake), and the status (seen at the done pulse).
class order_monitor extends uvm_monitor;
  `uvm_component_utils(order_monitor)

  virtual order_if vif;
  uvm_analysis_port #(order_result) ap;    // broadcasts each finished order_result

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual order_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "order_if not found in config_db")
  endfunction

  
  task run_phase(uvm_phase phase);
    order_result cur;
    trade_t t;
    int idx = 0;

    forever begin
        @(posedge vif.clk);
        if (vif.rst) continue;

        // Record an accepted order
        if (vif.in_valid && vif.in_ready) begin
            cur = order_result::type_id::create("res");

            cur.idx   = idx;
            cur.id    = vif.in_id;
            cur.side  = vif.in_side;
            cur.price = vif.in_price;
            cur.qty   = vif.in_qty;
        end

        // Record a completed trade
        if (vif.trade_valid && vif.trade_ready && cur != null) begin
            t.buy_id  = vif.trade_buy_id;
            t.sell_id = vif.trade_sell_id;
            t.price   = vif.trade_price;
            t.qty     = vif.trade_qty;

            cur.trades.push_back(t);
        end

        // Record completion and send to scoreboard
        if (vif.done_valid && cur != null) begin
            cur.status = vif.done_status;

            ap.write(cur);

            cur = null;
            idx++;
        end
    end
  endtask

endclass
