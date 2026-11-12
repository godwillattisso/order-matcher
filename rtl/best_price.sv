// best_price.sv : finds the best bid and best ask from the two occupancy bitmaps

module best_price #(
  parameter int NUM_LEVELS = 16
)(
  input  logic [NUM_LEVELS-1:0] bid_occ,
  input  logic [NUM_LEVELS-1:0] ask_occ,
  output logic                  bid_valid,  // 1 = at least one bid in the book
  output logic                  ask_valid,  // 1 = at least one ask in the book
  output logic [3:0]            best_bid,   // HIGHEST price with bids
  output logic [3:0]            best_ask    // LOWEST  price with asks
);

  always_comb begin : BestPrice
    
    best_bid = 0;
    best_ask = 0;

    for (int p = 0; p < NUM_LEVELS; p++) begin
      
      if (bid_occ[p]) begin
        
        best_bid = 4'(p);
      end
    end

    for (int p = NUM_LEVELS - 1; p >= 0; p-- ) begin
      
      if (ask_occ[p]) begin
        
        best_ask = 4'(p);
      end
    end
  end


  // Makes sure there is at least one bit that's = 1
  assign bid_valid = |bid_occ;  
  assign ask_valid = |ask_occ;  

endmodule
