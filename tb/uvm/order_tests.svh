// order_tests.svh : tests = which sequence to run, how many orders, which settings.
// Pick one at run time:  +UVM_TESTNAME=random_mix_test   (+N_ORDERS=<n>  +BP=<percent>)
class base_test extends uvm_test;
  `uvm_component_utils(base_test)
  order_env env;
  int n_orders = 1000;
  int bp_pct   = 0;
  virtual order_if vif;
  int n_accepted = 0;     // orders the DUT actually accepted (counted on the pins)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if ($value$plusargs("N_ORDERS=%d", n_orders)) `uvm_info("TEST", $sformatf("N_ORDERS=%0d", n_orders), UVM_LOW)
    if ($value$plusargs("BP=%d", bp_pct))         `uvm_info("TEST", $sformatf("BP=%0d%%", bp_pct), UVM_LOW)
    uvm_config_db#(int)::set(this, "env.agent.drv", "bp_pct", bp_pct);
    env = order_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual order_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "order_if not found in config_db")
  endfunction

  // Each test overrides this to start its own sequence.
  virtual task run_stimulus();
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);     // "don't end the test yet"
    fork
      forever begin                  // count accepted orders, for the timeout message
        @(posedge vif.clk);
        if (!vif.rst && vif.in_valid && vif.in_ready) n_accepted++;
      end
    join_none
    run_stimulus();
    wait_all_done();
    phase.drop_objection(this);      // "I'm done": the run phase ends, checking starts
  endtask

  // The sequences finish when the LAST ORDER IS ACCEPTED, not when it's done matching.
  // Wait until the scoreboard has a result for every accepted order (or time out).
  task wait_all_done();
    int waited = 0;
    #100ns;                          // let the last accepted order start
    while (env.sb.got.size() < n_accepted && waited < 100000) begin
      #10ns;
      waited++;
    end
    if (n_accepted == 0)
      `uvm_error("TIMEOUT", "the DUT accepted 0 orders: check the sequence/driver")
    else if (env.sb.got.size() < n_accepted)
      `uvm_error("TIMEOUT", $sformatf("only %0d of %0d accepted orders finished: check the monitor, or the FSM is stuck",
                                      env.sb.got.size(), n_accepted))
  endtask
endclass

class random_mix_test extends base_test;
  `uvm_component_utils(random_mix_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_stimulus();
    random_mix_seq seq = random_mix_seq::type_id::create("seq");
    seq.n_orders = n_orders;
    seq.start(env.agent.sqr);
  endtask
endclass
