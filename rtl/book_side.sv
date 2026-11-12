// book_side.sv : ONE side of the order book (used twice: once for bids, once for asks)


module book_side #(
  parameter int NUM_LEVELS  = 16,   // must match NUM_LEVELS  in ref_book.h
  parameter int LEVEL_DEPTH = 4     // must match LEVEL_DEPTH in ref_book.h
)(
  input  logic                  clk,
  input  logic                  rst,        // synchronous, active-high: empties every level

  input  logic [3:0]             sel_price,  // Identifies the price level you're currently working with. (Push, Pop, Dec, Count)

  input  logic                  push_en,    // add {push_id, push_qty} to the BACK of level sel_price
  input  logic [7:0]            push_id,    // Identifies which order is being added.
  input  logic [7:0]            push_qty,   // Specifies the quantity of the incoming order.

  input  logic                  pop_en,     // remove the FRONT order of level sel_price

  input  logic                  dec_en,     // Reduces the oldest order's quantity after a partial fill.
  input  logic [7:0]            dec_qty,    // Specifies how much quantity was filled.

  output logic [7:0]            head_id,    // front (oldest) order of level sel_price
  output logic [7:0]            head_qty,   // Lets the matching logic know how much quantity is available to match.
  output logic [2:0]            sel_count,  // number of orders at level sel_price (0..4)
  output logic [NUM_LEVELS-1:0] occ         // Lets best_price.sv identify which price levels have orders.
);

  // ---------------- storage ----------------
  logic [7:0] id_mem  [NUM_LEVELS][LEVEL_DEPTH];        // Stores the IDs of resting orders
  logic [7:0] qty_mem [NUM_LEVELS][LEVEL_DEPTH];        // Stores the remaining qty
  logic [2:0] count   [NUM_LEVELS];                     // Tracks the number of orders at each level


  always_ff @( posedge clk ) begin

    if (rst) begin
      for (int i = 0; i < NUM_LEVELS; i++) begin
        count[i] <= 0;
      end
    end
    else if (push_en) begin
      
      if (count[sel_price] < LEVEL_DEPTH) begin         // Only push if the selected price level slot is empty
        id_mem[sel_price][sel_count] <= push_id;        // Store new order ID in the next available slot
        qty_mem[sel_price][sel_count] <= push_qty;      // Store new order qty in that same slot
        count[sel_price] <= count[sel_price] + 1'b1;    // Increment count due to new order being added
      end 
    end
    else if (pop_en) begin
      if (count[sel_price] != 0) begin
        for (int i = 0; i < LEVEL_DEPTH - 1; i++) begin
          id_mem[sel_price][i] <= id_mem[sel_price][i+1];
          qty_mem[sel_price][i] <= qty_mem[sel_price][i+1];
        end
        count[sel_price] <= count[sel_price] - 1'b1;
        
      end
    end
    else if (dec_en) begin
      if (count[sel_price] != 0) begin
        qty_mem[sel_price][0] <= qty_mem[sel_price][0] - dec_qty;
        
      end     
    end 
  end
  
  // head_id and head_qty = slot 0 of level sel_price. One assign each.
  assign head_id  = id_mem[sel_price][0];
  assign head_qty = qty_mem[sel_price][0];

  // Shows the number of orders at the given price point
  assign sel_count = count[sel_price];  
  

  // Determines if the price level is empty or not. Occupied
    always_comb begin : occ_L

    for (int i = 0; i < NUM_LEVELS; i++) begin
      if (count[i] > 0) 
        occ[i] = 1;
        else
          occ[i] = 0; 

    end

  end

endmodule
