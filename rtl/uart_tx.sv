// uart_tx.sv : sends one byte on the serial line, UART "8N1" format.

module uart_tx #(
  parameter int CLKS_PER_BIT = 868
) (
  input  logic       clk,
  input  logic       rst,       // synchronous, active-high
  input  logic [7:0] data,      // byte to send
  input  logic       valid,     // 1 = data is waiting to be sent
  output logic       ready,     // 1 = idle, can take a byte
  output logic       tx         // serial output pin (1 when idle)
);

  typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
  state_t state;

  logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;  // cycles spent in the current bit
  logic [2:0]                      bit_idx;  // which data bit (0..7)
  logic [7:0]                      shift;    // the byte; bit 0 is always the next one to send
  logic                            bit_done; // the current bit has lasted CLKS_PER_BIT cycles

  assign ready    = (state == IDLE);
  assign bit_done = (clk_cnt == CLKS_PER_BIT - 1);


  always_ff @(posedge clk) begin
    if (rst) begin
      state   <= IDLE;
      tx      <= 1'b1;
      clk_cnt <= '0;
      bit_idx <= '0;
    end else begin
      
      case (state)
        IDLE: begin
          tx <= 1'b1;
          clk_cnt <= 0;

          if (valid) begin
            shift <= data;
            state <= START;
          end

        end

        START: begin
          tx <= 1'b0;
          
          if (bit_done) begin
            clk_cnt <= '0;
            bit_idx <='0;
            state <= DATA;
          end
          else begin
            clk_cnt <= clk_cnt + 1'b1;  //Keeping counting clock cycles
          end
        end

        DATA: begin
          tx <= shift[0];     

          if (bit_done) begin
            clk_cnt <= '0;
            shift <= shift >> 1;

            if (bit_idx == 3'd7) 
              state <= STOP;                              //All 8 bits are transmitted
            else 
              bit_idx <= bit_idx + 1'b1;
          end
          else
            clk_cnt <= clk_cnt + 1'd1; 
        end

        STOP: begin
          tx <= 1'b1;

          if (bit_done) begin
            clk_cnt <= 1'b0;
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
