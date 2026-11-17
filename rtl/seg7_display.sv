// seg7_display.sv : shows best bid (left 2 digits) and best ask (right 2 digits).  (GIVEN)


module seg7_display (
  input  logic       clk,
  input  logic       bid_valid,
  input  logic [3:0] best_bid,
  input  logic       ask_valid,
  input  logic [3:0] best_ask,
  output logic [6:0] seg,     // {g,f,e,d,c,b,a}, active-low
  output logic [3:0] an       // digit enables, an[3] = leftmost, active-low
);

  localparam logic [3:0] DASH = 4'd10, BLANK = 4'd11;

  logic [17:0] refresh = '0;   // 100 MHz / 2^16 ≈ 1.5 kHz per digit
  always_ff @(posedge clk) refresh <= refresh + 1'b1;
  wire [1:0] digit = refresh[17:16];

  // the 4 digits to show (tens and ones of each price)
  logic [3:0] d3, d2, d1, d0, cur;
  always_comb begin
    d3 = bid_valid ? (best_bid >= 10 ? 4'd1 : BLANK) : DASH;
    d2 = bid_valid ? (best_bid >= 10 ? best_bid - 4'd10 : best_bid) : DASH;
    d1 = ask_valid ? (best_ask >= 10 ? 4'd1 : BLANK) : DASH;
    d0 = ask_valid ? (best_ask >= 10 ? best_ask - 4'd10 : best_ask) : DASH;
    case (digit)
      2'd3: begin an = 4'b0111; cur = d3; end
      2'd2: begin an = 4'b1011; cur = d2; end
      2'd1: begin an = 4'b1101; cur = d1; end
      default: begin an = 4'b1110; cur = d0; end
    endcase
  end

  always_comb begin
    case (cur)               //  gfedcba
      4'd0:    seg = 7'b1000000;
      4'd1:    seg = 7'b1111001;
      4'd2:    seg = 7'b0100100;
      4'd3:    seg = 7'b0110000;
      4'd4:    seg = 7'b0011001;
      4'd5:    seg = 7'b0010010;
      4'd6:    seg = 7'b0000010;
      4'd7:    seg = 7'b1111000;
      4'd8:    seg = 7'b0000000;
      4'd9:    seg = 7'b0010000;
      DASH:    seg = 7'b0111111;   // only segment g
      default: seg = 7'b1111111;   // blank
    endcase
  end

endmodule
