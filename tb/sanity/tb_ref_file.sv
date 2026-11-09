// tb_ref_file.sv - Check 3 (file-based): SystemVerilog writes orders to a file, runs the
// C++ reference model on it with $system, then reads the expected results back.
// This is the exact flow the Day 4 scoreboard will use (replaces the DPI version).
//
// Run from sim\ref_file. Needs model\ref_runner.exe built first.
`timescale 1ns/1ps
module tb_ref_file;
  int fd, rc, n;
  string kind;
  int idx, ntr, status, b, s, p, q;
  int t_count, pass_ok;

  initial begin
    // 1. Write the orders (same two orders as the DPI version)
    fd = $fopen("orders.txt", "w");
    if (fd == 0) begin $display("REF MODEL FILE FAILED: cannot create orders.txt"); $finish; end
    $fdisplay(fd, "1 0 10 5");   // BUY  5 @ 10 -> rests
    $fdisplay(fd, "2 1 9 8");    // SELL 8 @ 9  -> trades 5 @ 10, 3 rest at 9
    $fclose(fd);

    // 2. Run the C++ model on them
    rc = $system("..\\..\\model\\ref_runner.exe orders.txt expected.txt");
    if (rc != 0) begin
      $display("REF MODEL FILE FAILED: ref_runner returned %0d", rc);
      $finish;
    end

    // 3. Read the expected results back
    fd = $fopen("expected.txt", "r");
    if (fd == 0) begin $display("REF MODEL FILE FAILED: cannot open expected.txt"); $finish; end
    t_count = 0;
    pass_ok = 0;
    while ($fscanf(fd, "%s", kind) == 1) begin
      if (kind == "S") begin
        n = $fscanf(fd, "%d %d %d", idx, ntr, status);
        $display("order %0d: %0d trades, status %0d (0 = rested)", idx, ntr, status);
      end else if (kind == "T") begin
        n = $fscanf(fd, "%d %d %d %d %d", idx, b, s, p, q);
        $display("  trade (order %0d): buy_id=%0d sell_id=%0d price=%0d qty=%0d", idx, b, s, p, q);
        t_count++;
        if (idx == 1 && b == 1 && s == 2 && p == 10 && q == 5) pass_ok = 1;
      end
    end
    $fclose(fd);

    if (pass_ok && t_count == 1) $display("REF MODEL FILE PASSED");
    else                         $display("REF MODEL FILE FAILED");
    $finish;
  end
endmodule
