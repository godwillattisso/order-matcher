// tb_board.sv : simulates the WHOLE board design (top.sv) the way the PC will talk to it.  (GIVEN)
//
//  this testbench (acts like the PC)                 top.sv (acts like the board)
//   send 5 bytes: A5 id side price qty  ──RsRx──►  uart_rx → order_rx → engine
//   read 'T' / 'D' messages             ◄──RsTx──  uart_tx ◄ report_tx ◄ engine
//
// Then the same check as the scoreboard: run the C++ model on the same orders and compare
// every trade and status. Also checks the cycle counter: RESTED/REJECTED = 4 + 2 per trade,
// FILLED = 2 + 2 per trade (the FILLED order skips CHECK→REST: its last FILL goes straight to DONE).
//
// If this passes, the only new things on the real board are the pins, the clock and the PC script.
// CLKS_PER_BIT is 8 here (not 868) so the simulation is fast.

`timescale 1ns/1ps
module tb_board;
  localparam int CPB      = 8;
  localparam int N_ORDERS = 300;

  logic clk = 0;
  always #5 clk = ~clk;

  logic        btnC = 0, RsRx = 1, RsTx, dp;
  logic [6:0]  seg;
  logic [3:0]  an;
  logic [15:0] led;

  top #(.CLKS_PER_BIT(CPB)) dut (.clk, .btnC, .RsRx, .RsTx, .seg, .dp, .an, .led);

  // ---- PC side of the serial line ----
  task automatic pc_send(input logic [7:0] b);
    RsRx = 0;                                   // start bit
    repeat (CPB) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
      RsRx = b[i];
      repeat (CPB) @(posedge clk);
    end
    RsRx = 1;                                   // stop bit
    repeat (CPB) @(posedge clk);
  endtask

  int timeout_cycles;
  task automatic pc_recv(output logic [7:0] b, output bit ok);
    ok = 0;
    timeout_cycles = 0;
    while (RsTx !== 1'b0) begin                 // wait for a start bit
      @(posedge clk);
      if (++timeout_cycles > 20000) return;
    end
    repeat (CPB / 2) @(posedge clk);            // middle of the start bit
    for (int i = 0; i < 8; i++) begin
      repeat (CPB) @(posedge clk);
      b[i] = RsTx;
    end
    repeat (CPB) @(posedge clk);                // stop bit
    ok = (RsTx === 1'b1);
  endtask

  // ---- one order: send it, read the replies until its 'D' ----
  int   errors = 0, n_trades_total = 0, out_fd, ord_fd;
  string ref_exe = "..\\..\\model\\ref_runner.exe";

  task automatic do_order(input int idx, input logic [7:0] id, input bit side,
                          input logic [3:0] price, input logic [7:0] qty);
    logic [7:0] m [5];
    bit ok;
    int ntr = 0;
    string tlines = "";
    pc_send(8'hA5); pc_send(id); pc_send({7'd0, side}); pc_send({4'd0, price}); pc_send(qty);
    $fdisplay(ord_fd, "%0d %0d %0d %0d", id, side, price, qty);
    forever begin
      pc_recv(m[0], ok);
      if (!ok) begin
        errors++;
        $display("  FAIL order %0d: no reply from the board (or bad stop bit)", idx);
        return;
      end
      if (m[0] == 8'h54) begin                  // 'T' buy sell price qty
        for (int i = 1; i < 5; i++) pc_recv(m[i], ok);
        ntr++;
        tlines = {tlines, $sformatf("T %0d %0d %0d %0d %0d\n", idx, m[1], m[2], m[3], m[4])};
      end else if (m[0] == 8'h44) begin         // 'D' id status cycles
        for (int i = 1; i < 4; i++) pc_recv(m[i], ok);
        if (m[1] != id) begin
          errors++;
          $display("  FAIL order %0d: done reported id %0d, expected %0d", idx, m[1], id);
        end
        begin
          int expect_cyc;
          expect_cyc = (m[2] == 1) ? 2 + 2 * ntr : 4 + 2 * ntr;
          if (m[3] != expect_cyc) begin
            errors++;
            $display("  FAIL order %0d: cycle counter %0d, expected %0d (status %0d, %0d trades)",
                     idx, m[3], expect_cyc, m[2], ntr);
          end
        end
        $fwrite(out_fd, "S %0d %0d %0d\n%s", idx, ntr, m[2], tlines);
        n_trades_total += ntr;
        return;
      end else begin
        errors++;
        $display("  FAIL order %0d: unknown message type %h", idx, m[0]);
        return;
      end
    end
  endtask

  // ---- compare hw_out.txt with what the C++ model says (expected.txt) ----
  task automatic compare_with_model();
    int fe, fh, rc, n = 0;
    string le, lh;
    rc = $system({ref_exe, " board_orders.txt board_expected.txt"});
    if (rc != 0) begin
      errors++;
      $display("  FAIL: '%s' returned %0d. Is model\\ref_runner.exe built?", ref_exe, rc);
      return;
    end
    fe = $fopen("board_expected.txt", "r");
    fh = $fopen("board_hw.txt", "r");
    while (!$feof(fe) || !$feof(fh)) begin
      le = ""; lh = "";
      void'($fgets(le, fe));
      void'($fgets(lh, fh));
      while (le.len() > 0 && (le[le.len()-1] == "\n" || le[le.len()-1] == "\r")) le = le.substr(0, le.len()-2);
      while (lh.len() > 0 && (lh[lh.len()-1] == "\n" || lh[lh.len()-1] == "\r")) lh = lh.substr(0, lh.len()-2);
      if (le == "" && lh == "") continue;
      n++;
      if (le != lh) begin
        errors++;
        if (errors < 10) $display("  MISMATCH line %0d: board='%s'  C++='%s'", n, lh, le);
      end
    end
    $fclose(fe); $fclose(fh);
    $display("Compared %0d result lines with the C++ model", n);
  endtask

  initial begin
    void'($value$plusargs("REF=%s", ref_exe));
    $display("=== tb_board: %0d orders through UART → engine → UART ===", N_ORDERS);
    ord_fd = $fopen("board_orders.txt", "w");
    out_fd = $fopen("board_hw.txt", "w");

    repeat (40) @(posedge clk);                 // power-on reset runs by itself
    if (dut.u_eng.bid_valid !== 1'b0 || dut.u_eng.ask_valid !== 1'b0) begin
      errors++; $display("  FAIL: book not empty after power-on reset");
    end

    for (int i = 0; i < N_ORDERS; i++) begin
      logic [3:0] price;
      logic [7:0] qty;
      price = 4'($urandom_range(11, 4));
      qty   = ($urandom_range(9, 0) == 0) ? 8'($urandom_range(60, 20))   // 10% whales
                                          : 8'($urandom_range(8, 1));
      do_order(i, 8'(i), 1'($urandom_range(1, 0)), price, qty);
      if (errors > 10) break;
    end
    $fclose(ord_fd);
    $fclose(out_fd);

    compare_with_model();

    if (led[15:8] != 8'(N_ORDERS) || led[7:0] != 8'(n_trades_total)) begin
      errors++;
      $display("  FAIL: LEDs show %0d orders / %0d trades, expected %0d / %0d (mod 256)",
               led[15:8], led[7:0], N_ORDERS % 256, n_trades_total % 256);
    end

    $display("%0d orders, %0d trades", N_ORDERS, n_trades_total);
    if (errors == 0) $display("TB_BOARD PASSED");
    else             $display("TB_BOARD FAILED: %0d error(s)", errors);
    $finish;
  end

  initial begin
    #100ms;
    $display("TB_BOARD FAILED: timeout");
    $finish;
  end
endmodule
