# synth_book.tcl : synthesize book_side alone and report how much FPGA it uses.
# Run from C:\dev\order-matcher\sim\synth (see Day 2 guide, Step 7).
read_verilog -sv ../../rtl/book_side.sv
synth_design -top book_side -part xc7a35tcpg236-1 -mode out_of_context
report_utilization -file book_side_util.txt
puts "Done. Open sim\\synth\\book_side_util.txt and find 'Slice Registers' and 'Slice LUTs'."
