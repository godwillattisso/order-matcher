// order_item.svh : ONE order = one UVM "sequence item" (the unit the testbench sends).
class order_item extends uvm_sequence_item;
  `uvm_object_utils(order_item)

  rand bit [7:0] id;
  rand bit       side;     // 0 = BUY, 1 = SELL
  rand bit [3:0] price;
  rand bit [7:0] qty;

  constraint c_legal {
    qty inside {[1:255]};
  }

  constraint c_default {
    soft price inside {[4:11]};
    soft qty inside {[1:8]};
  }

  function new(string name = "order_item");
    super.new(name);
  endfunction

  function string convert2string();
    // one-line description for log messages
    return $sformatf("id = %0d %s %0d @ %0d", id, side ? "SELL" : "BUY", qty, price);
  
  endfunction
endclass

// What the monitor saw for one order: the order itself, its trades, and its status.
typedef struct packed { int buy_id; int sell_id; int price; int qty; } trade_t;   // packed: compares with == in one step

class order_result extends uvm_object;
  `uvm_object_utils(order_result)

  int     idx;          // 0, 1, 2, ... in the order the DUT accepted them
  int     id, side, price, qty;
  trade_t trades[$];    // every trade this order made, in order
  int     status;       // 0 RESTED, 1 FILLED, 2 REJECT_FULL

  function new(string name = "order_result");
    super.new(name);
  endfunction
endclass
