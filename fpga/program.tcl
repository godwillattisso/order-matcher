# program.tcl : load build\order_matcher.bit onto the Basys3 over USB.  (GIVEN)
# Run from the repo folder:   scripts\program_fpga.bat   (board plugged in and switched ON)
# The design is lost when the board is switched off; run this again after power-up.

set root [file normalize [file join [file dirname [info script]] ..]]
set bit  [file join $root build order_matcher.bit]

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
close_hw_manager
puts "PROGRAMMED: $bit"
