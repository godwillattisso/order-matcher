# build.tcl : synthesis → place → route → reports → bitstream, with no Vivado project.  (GIVEN)
# Run from the repo folder:   scripts\build_fpga.bat
# Outputs go to build\ :
#   utilization_hier.rpt  flip-flops / LUTs per module (compare book_side with your 1,072 prediction)
#   utilization.rpt       totals after routing
#   timing.rpt            WNS (worst negative slack): >= 0 means the design meets 100 MHz
#   order_matcher.bit     the file you load onto the board

set root [file normalize [file join [file dirname [info script]] ..]]
set out  [file join $root build]
file mkdir $out

read_verilog -sv [list \
  $root/rtl/book_side.sv  $root/rtl/best_price.sv  $root/rtl/match_engine.sv \
  $root/rtl/uart_rx.sv    $root/rtl/uart_tx.sv     $root/rtl/order_rx.sv \
  $root/rtl/report_tx.sv  $root/rtl/seg7_display.sv $root/rtl/top.sv ]
read_xdc $root/fpga/basys3.xdc

# Basys3 = Artix-7 xc7a35t, package cpg236, speed grade -1
synth_design -top top -part xc7a35tcpg236-1
report_utilization -hierarchical -file $out/utilization_hier.rpt

opt_design
place_design
route_design

report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing.rpt
write_bitstream -force $out/order_matcher.bit

puts "=========================================================="
puts " BUILD DONE: $out/order_matcher.bit"
puts " Check build/timing.rpt (WNS) and build/utilization_hier.rpt"
puts "=========================================================="
