if {![info exists ::env(COCOTANG_FPGA_ROOT)]} {
    error "COCOTANG_FPGA_ROOT is not set"
}
if {![info exists ::env(COCOTANG_PROJECT)]} {
    set ::env(COCOTANG_PROJECT) CoCoTANG.gprj
}
if {![info exists ::env(COCOTANG_TOP)]} {
    set ::env(COCOTANG_TOP) top_coco3
}
if {![info exists ::env(COCOTANG_OUTPUT)]} {
    set ::env(COCOTANG_OUTPUT) CoCoTANG
}
cd $::env(COCOTANG_FPGA_ROOT)
open_project [file join $::env(COCOTANG_FPGA_ROOT) $::env(COCOTANG_PROJECT)]
set_option -top_module $::env(COCOTANG_TOP)
set_option -output_base_name $::env(COCOTANG_OUTPUT)
set_option -verilog_std sysv2017
set_option -route_option 1
# Gowin retains placement settings between runs. Select each named video
# mode explicitly so its result does not depend on the previous build.
if {$::env(COCOTANG_TOP) eq "top_coco3_ntsc_svideo" ||
    $::env(COCOTANG_TOP) eq "top_coco3_ypbpr"} {
    set_option -place_option 1
} elseif {$::env(COCOTANG_TOP) eq "top_coco3_rgb"} {
    # Timing-checked with the current motherboard's address-bus wiring.
    set_option -place_option 1
    set_option -route_option 0
    set_option -replicate_resources 1
    set_option -route_maxfan 16
} elseif {$::env(COCOTANG_TOP) eq "top_coco3"} {
    set_option -place_option 2
}
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
run all
