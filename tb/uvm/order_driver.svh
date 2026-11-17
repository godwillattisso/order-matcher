// order_driver.svh : turns order_items into pin wiggles on the DUT's input handshake.
// Also plays the "trade receiver": drives trade_ready, randomly low if bp_pct > 0.
class order_driver extends uvm_driver #(order_item);
  `uvm_component_utils(order_driver)

  virtual order_if vif;
  int bp_pct  = 0;    // % of cycles trade_ready is 0 (back-pressure)
  int max_gap = 3;    // random idle cycles between orders: 0..max_gap

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual order_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "order_if not found in config_db")
    void'(uvm_config_db#(int)::get(this, "", "bp_pct", bp_pct));
  endfunction

  task run_phase(uvm_phase phase);
    vif.in_valid    = 0;
    vif.in_id       = 0;
    vif.in_side     = 0;
    vif.in_price    = 0;
    vif.in_qty      = 0;
    vif.trade_ready = 1;
    fork
      drive_trade_ready();
    join_none
    @(negedge vif.clk iff !vif.rst);     // wait for reset to finish
    forever begin
      seq_item_port.get_next_item(req);
      `uvm_info("DRV", {"sending ", req.convert2string()}, UVM_HIGH)
      drive_order(req);
      seq_item_port.item_done();
    end
  endtask

  // One order through the valid/ready handshake. Inputs change on the FALLING edge,
  // so they're stable when the DUT samples them on the rising edge.
  task drive_order(order_item it);

    // Wait 0 to max_gap random clock cycles
    repeat ($urandom_range(max_gap, 0))
        @(negedge vif.clk);

    // Wait until the DUT is ready to accept an order
    while (!vif.in_ready)
        @(negedge vif.clk);

    //Transfer the order data to the DUT
    vif.in_valid = 1'b1;
    vif.in_id    = it.id;
    vif.in_side  = it.side;
    vif.in_price = it.price;
    vif.in_qty   = it.qty;

    // Wait one falling edge
    // The DUT accepts the order at the rising edge in between
    @(negedge vif.clk);

    //Stop presenting the order
    vif.in_valid = 1'b0;

  endtask

  task drive_trade_ready();
    forever begin
      @(negedge vif.clk);
      vif.trade_ready = (bp_pct == 0) ? 1'b1 : ($urandom_range(99, 0) >= bp_pct);
    end
  endtask
endclass
