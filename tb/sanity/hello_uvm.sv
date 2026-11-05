// hello_uvm.sv - Check 1: proves the Vivado simulator can compile and run UVM.
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class hello_test extends uvm_test;
  `uvm_component_utils(hello_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("HELLO", "UVM is working in the Vivado simulator", UVM_LOW)
    #10;
    phase.drop_objection(this);
  endtask
endclass

module tb_hello_uvm;
  initial run_test("hello_test");
endmodule
