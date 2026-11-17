// uart_rx.sv : receives one byte from the serial line, UART "8N1" format.
//
//   line idle = 1 | start bit = 0 | 8 data bits, LSB first | stop bit = 1

module uart_rx #(
  parameter int CLKS_PER_BIT = 868
) (
  input  logic       clk,
  input  logic       rst,       // synchronous, active-high
  input  logic       rx,        // serial input pin (1 when idle)
  output logic [7:0] data,      // the byte received
  output logic       valid      // 1 for one cycle when data holds a new byte
);

  // 2-flip-flop synchronizer, due to data being asynchronus
  logic rx_meta, rx_sync;
  always_ff @(posedge clk) begin
    if (rst) begin
      rx_meta <= 1'b1;
      rx_sync <= 1'b1;
    end else begin
      rx_meta <= rx;
      rx_sync <= rx_meta;      // use ONLY rx_sync below
    end
  end

  typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
  state_t state;

  logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;     // When should I receive a bit
  logic [2:0]                      bit_idx;     // How many Bits have I received
  logic [7:0]                      shift;       // What bit did I receive


  // Use rx_sync (never rx). valid is a 1-cycle pulse: it's set to 0 at the top of every cycle, and only STOP sets it to 1.
  always_ff @(posedge clk) begin
    if (rst) begin
      state   <= IDLE;
      valid   <= 1'b0;
      clk_cnt <= '0;
      bit_idx <= '0;
    end else begin
      valid <= 1'b0;

      case (state)
        IDLE: begin
          clk_cnt <= 1'b0;
          if (rx_sync == 0)
            state <= START;
        end

        START: begin
          if (clk_cnt == CLKS_PER_BIT/2 - 1) begin
            clk_cnt <=1'b0;
            bit_idx <= 1'b0;

            if (rx_sync == 0)
              state <= DATA;
            else
            state <= IDLE;
          end 
          else
          clk_cnt <= clk_cnt + 1'b1; 
        end

        DATA: begin
          if (clk_cnt == CLKS_PER_BIT - 1) begin
            clk_cnt <= 1'b0;
            shift <= {rx_sync, shift[7:1]};
          
            if (bit_idx == 3'd7)
              state <= STOP;

          else
          bit_idx <= bit_idx + 1'b1;
          end
          else
          clk_cnt <= clk_cnt + 1'b1;
        end


        STOP: begin
          if (clk_cnt == CLKS_PER_BIT - 1)begin
          clk_cnt <= 1'b0;
          data <= shift;
          valid <= rx_sync;        // Stop bit must be 1(UART)
          state <= IDLE;
          end
          else 
          clk_cnt <= clk_cnt + 1'b1;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
