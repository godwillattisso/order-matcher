// order_env.svh : agent (sequencer + driver + monitor) and env (agent + scoreboard).
typedef uvm_sequencer #(order_item) order_sequencer;

class order_agent extends uvm_agent;
  `uvm_component_utils(order_agent)
  order_sequencer sqr;
  order_driver    drv;
  order_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = order_sequencer::type_id::create("sqr", this);
    drv = order_driver::type_id::create("drv", this);
    mon = order_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);   // sequencer hands items to the driver
  endfunction
endclass

class order_env extends uvm_env;
  `uvm_component_utils(order_env)
  order_agent      agent;
  order_scoreboard sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = order_agent::type_id::create("agent", this);
    sb    = order_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.mon.ap.connect(sb.imp);                     // every monitor result goes to the scoreboard
  endfunction
endclass
