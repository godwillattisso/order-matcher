// tb_uart.sv : unit test for YOUR uart_tx and uart_rx.  (GIVEN)


`timescale 1ns/1ps
module tb_uart;
  localparam int CPB = 16;

  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  logic [7:0] tx_data;
  logic       tx_valid = 0, tx_ready, line;
  logic [7:0] rx_data;
  logic       rx_valid;
  logic       glitch = 0;            // forces the wire to 0 for U4
  wire        rx_in = line & ~glitch;

  uart_tx #(.CLKS_PER_BIT(CPB)) u_tx (.clk, .rst, .data(tx_data), .valid(tx_valid), .ready(tx_ready), .tx(line));
  uart_rx #(.CLKS_PER_BIT(CPB)) u_rx (.clk, .rst, .rx(rx_in), .data(rx_data), .valid(rx_valid));

  int errors = 0;
  logic [7:0] got [$];
  always @(posedge clk) if (rx_valid) got.push_back(rx_data);

  task automatic check(bit ok, string msg);
    if (!ok) begin errors++; $display("  FAIL: %s", msg); end
  endtask

  // send one byte through uart_tx using the valid/ready handshake
  task automatic send(input logic [7:0] b);
    @(negedge clk);
    tx_data  = b;
    tx_valid = 1;
    do @(posedge clk); while (!tx_ready);   // taken on this edge
    @(negedge clk);
    tx_valid = 0;
  endtask

  task automatic wait_idle();
    // wait until tx is idle and the receiver has had time to finish
    do @(posedge clk); while (!tx_ready);
    repeat (CPB * 2) @(posedge clk);
  endtask

  initial begin
    $display("=== tb_uart ===");
    repeat (3) @(posedge clk);
    rst = 0;
    repeat (2) @(posedge clk);

    // U1
    check(line === 1'b1, "U1 idle line should be 1");
    check(tx_ready === 1'b1, "U1 tx ready should be 1 when idle");
    $display("U1 idle state            %s", errors == 0 ? "ok" : "FAILED");

    // U2: watch the wire bit by bit
    begin
      int e0;
      logic [9:0] expected;
      e0       = errors;
      expected = {1'b1, 8'h35, 1'b0};             // stop, data (MSB..LSB), start → sent LSB first
      fork
        send(8'h35);
        begin
          @(negedge line);                          // start bit begins
          repeat (CPB / 2) @(posedge clk);          // middle of the start bit
          for (int i = 0; i < 10; i++) begin
            check(line === expected[i], $sformatf("U2 bit %0d on the wire: got %b, expected %b", i, line, expected[i]));
            if (i == 4) check(tx_ready === 1'b0, "U5 ready must be 0 while sending");
            repeat (CPB) @(posedge clk);
          end
        end
      join
      wait_idle();
      check(got.size() == 1 && got[0] == 8'h35, $sformatf("U2 rx should receive 35, got %0d byte(s)%s",
            got.size(), got.size() ? $sformatf(", first = %h", got[0]) : ""));
      $display("U2 0x35 on the wire       %s", errors == e0 ? "ok" : "FAILED");
      got.delete();
    end

    // U3: all 256 values back to back
    begin
      int e0;
      logic [7:0] v;
      bit bad;
      e0 = errors;
      for (int b = 0; b < 256; b++) begin
        v = b;                                    // plain 8-bit copy of the counter
        send(v);
      end
      wait_idle();
      check(got.size() == 256, $sformatf("U3 expected 256 bytes, received %0d", got.size()));
      bad = 0;
      for (int b = 0; b < got.size(); b++) begin
        v = b;
        if (!bad && got[b] !== v) begin             // report only the first wrong byte
          check(0, $sformatf("U3 byte %0d: got %b, expected %b", b, got[b], v));
          bad = 1;
        end
      end
      $display("U3 256 bytes loopback     %s", errors == e0 ? "ok" : "FAILED");
      got.delete();
    end

    // U4: glitch shorter than half a bit
    begin
      int e0;
      e0 = errors;
      @(negedge clk);
      glitch = 1;
      repeat (CPB / 4) @(negedge clk);
      glitch = 0;
      repeat (CPB * 12) @(posedge clk);
      check(got.size() == 0, $sformatf("U4 a glitch produced %0d byte(s)", got.size()));
      send(8'hC3);                                  // and rx still works afterwards
      wait_idle();
      check(got.size() == 1 && got[0] == 8'hC3, "U4 byte after the glitch not received correctly");
      $display("U4 glitch ignored         %s", errors == e0 ? "ok" : "FAILED");
    end

    if (errors == 0) $display("TB_UART PASSED");
    else             $display("TB_UART FAILED: %0d error(s)", errors);
    $finish;
  end

  initial begin
    #5ms;
    $display("TB_UART FAILED: timeout (is ready ever 1? is valid ever pulsed?)");
    $finish;
  end
endmodule