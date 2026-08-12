# program.tcl — Vivado Hardware Manager programming script
open_hw_manager
if {[catch {connect_hw_server} err]} {
    puts "Error connecting to hw_server: $err"
    exit 1
}
if {[catch {open_hw_target} err]} {
    puts "Error opening hw_target: $err"
    disconnect_hw_server
    exit 1
}
set devices [get_hw_devices]
if {[llength $devices] == 0} {
    puts "No JTAG devices found!"
    close_hw_target
    disconnect_hw_server
    exit 1
}
set device [lindex $devices 0]
current_hw_device $device
puts "Programming device: $device"
set_property PROGRAM.FILE {build/kavacha_arty_a7.bit} $device
if {[catch {program_hw_devices $device} err]} {
    puts "Error programming device: $err"
    close_hw_target
    disconnect_hw_server
    exit 1
}
puts "Successfully programmed $device!"
close_hw_target
disconnect_hw_server
close_hw_manager
