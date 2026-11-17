// order_seqs_more.svh : more sequences = more kinds of market, to reach every coverage bin.

// market_seq: random orders with knobs. random_mix_seq is one setting of these knobs;
// the tests below use other settings (calm, frantic, whales, one-sided).
class market_seq extends uvm_sequence #(order_item);
  `uvm_object_utils(market_seq)

  int n_orders  = 200;
  int price_lo  = 4,  price_hi = 11;   // price range
  int qty_lo    = 1,  qty_hi   = 8;    // normal order size
  int whale_pct = 10;                  // % big orders (qty 40..150)
  int buy_pct   = 50;                  // % BUY orders
  static int next_id = 0;              // ids keep counting across sequences

  function new(string name = "market_seq");
    super.new(name);
  endfunction

  task body();
    order_item it;
    bit        whale, buy;
    int        cur_id;
    for (int i = 0; i < n_orders; i++) begin
      it     = order_item::type_id::create($sformatf("mkt%0d", i));
      whale  = ($urandom_range(99, 0) < whale_pct);
      buy    = ($urandom_range(99, 0) < buy_pct);
      cur_id = next_id % 256;
      start_item(it);
      if (!it.randomize() with { id == local::cur_id; side == !local::buy; })
        `uvm_fatal("RAND", "randomize failed")
      // Price and size are picked HERE, not by the solver. In Vivado, order_item's soft
      // defaults (qty 1..8, price 4..11) stayed active even with constraint_mode(0), so
      // qty 9..19 never happened. Coverage caught it: the qty coverpoint was stuck at 67%.
      it.price = $urandom_range(price_hi, price_lo);
      it.qty   = whale ? $urandom_range(150, 40) : $urandom_range(qty_hi, qty_lo);
      next_id++;
      finish_item(it);
    end
  endtask
endclass


// fill_level_seq: fills price levels to their limit of 4, then keeps going, so orders get REJECTED.
// Uses the extreme prices (BUY at 0-1, SELL at 14-15), where the other side almost never trades.
class fill_level_seq extends uvm_sequence #(order_item);
  `uvm_object_utils(fill_level_seq)

  int n_rounds = 10;          // one round = 5 orders, same side and price

  function new(string name = "fill_level_seq");
    super.new(name);
  endfunction

  task body();
    order_item it;
    bit        s;
    int        p;
    // ===== TODO: fill price levels until orders get rejected =====
    // for each round r (0 .. n_rounds-1):
    //   s = random side ($urandom_range(1, 0): 0 BUY, 1 SELL)
    //   p = a price far from the other side: SELL -> $urandom_range(15, 14), BUY -> $urandom_range(1, 0)
    //   send 5 orders (k = 0..4), all with that side and price, qty 1..3:
    //     it = order_item::type_id::create($sformatf("fill%0d_%0d", r, k));
    //     it.c_default.constraint_mode(0);       // switch off the soft defaults (see market_seq)
    //     start_item(it);
    //     randomize with: id == (local::r * 5 + local::k) % 256; side == local::s;
    //                     price == local::p; qty inside {[1:3]};   (uvm_fatal if it fails)
    //     finish_item(it);
    // Why 5: a level holds 4, so the 5th order of each round can't fit.
  endtask
endclass
