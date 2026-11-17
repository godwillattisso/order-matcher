// order_seqs.svh : sequences = recipes that generate streams of orders.
class random_mix_seq extends uvm_sequence #(order_item);
  `uvm_object_utils(random_mix_seq)

  int n_orders  = 1000;   // set by the test
  int whale_pct = 10;     // % of orders that are big (sweep several levels)

  function new(string name = "random_mix_seq");
    super.new(name);
  endfunction

  task body();
    order_item it;

    //Generate n_orders random orders
    for (int i = 0; i < n_orders; i++) begin
        // Create a new order object
        it = order_item::type_id::create($sformatf("ord%0d", i));
        // Request permission to send the order
        start_item(it);

        // 10% chance of generating a whale order
        if ($urandom_range(99, 0) < whale_pct) begin

            // Whale order: quantity between 20 and 60
            if (!it.randomize() with {
                id == local::i % 256;
                qty inside {[20:60]};
            })
                `uvm_fatal("RAND", "randomize failed")
        end
        else begin
            // Normal order: uses soft default constraints
            if (!it.randomize() with {
                id == local::i % 256;
            })
                `uvm_fatal("RAND", "randomize failed")
        end

        // Send the order to the driver
        finish_item(it);

    end
endtask
endclass
