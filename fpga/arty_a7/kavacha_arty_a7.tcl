# =============================================================================
# kavacha_arty_a7.tcl — Vivado batch flow to a BITSTREAM for the Arty A7-100T.
#   vivado -mode batch -source kavacha_arty_a7.tcl -tclargs <BUILD_DIR>
#
# Before running, build the demo firmware and copy it into <BUILD_DIR> as
# firmware.mem (the RAM $readmemh init):
#   cd sw && ./build_fpga_hello.sh && cp firmware.mem <BUILD_DIR>/firmware.mem
# =============================================================================
set fpga_dir  [file normalize [file dirname [info script]]]
set build_dir [file normalize [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "$fpga_dir/build"}]]
set part      xc7a100tcsg324-1


file mkdir $build_dir
cd $build_dir

if {![file exists $build_dir/firmware.mem]} {
  if {[file exists $fpga_dir/../../sw/firmware.mem]} {
    file copy -force $fpga_dir/../../sw/firmware.mem $build_dir/firmware.mem
  } else {
    error "Missing firmware image $build_dir/firmware.mem. Build it first: cd sw && ./build_fpga_hello.sh"
  }
}


set fp [open $fpga_dir/kavacha_arty_a7.f r]
while {[gets $fp line] >= 0} {
  set line [string trim $line]
  if {$line eq "" || [string match "#*" $line]} { continue }
  read_verilog -sv [file normalize $fpga_dir/$line]
}
close $fp

read_xdc $fpga_dir/kavacha_arty_a7.xdc
set_property part $part [current_project]
set_property top kavacha_arty_a7 [current_fileset]
set_property include_dirs [list [file normalize $fpga_dir/../../rtl/common]] [current_fileset]

# firmware.mem must be in $build_dir (one 32-bit hex word per line)
add_files -norecurse $build_dir/firmware.mem
set_property file_type {Memory Initialization Files} [get_files firmware.mem]

synth_design -top kavacha_arty_a7 -part $part
opt_design
place_design
route_design
report_utilization    -file $build_dir/util.rpt
report_timing_summary -file $build_dir/timing.rpt
write_bitstream -force $build_dir/kavacha_arty_a7.bit
puts "DONE: $build_dir/kavacha_arty_a7.bit"
# Program:  openFPGALoader -b arty_a7_100t kavacha_arty_a7.bit
