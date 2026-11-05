// hello_dpi.sv - Check 2: calls add_two() from hello_dpi.c through DPI-C.
`timescale 1ns/1ps
module tb_hello_dpi;
  import "DPI-C" function int add_two(input int a, input int b);

  int r;
  initial begin
    r = add_two(2, 3);
    if (r == 5) $display("DPI PASSED: 2 + 3 = %0d", r);
    else        $display("DPI FAILED: got %0d", r);
    $finish;
  end
endmodule
