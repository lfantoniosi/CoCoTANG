if {![info exists ::env(COCOTANG_FPGA_ROOT)]} {
    error "COCOTANG_FPGA_ROOT is not set"
}
cd $::env(COCOTANG_FPGA_ROOT)
open_project [file join $::env(COCOTANG_FPGA_ROOT) CoCoTANG.gprj]
set_option -top_module top
set_option -output_base_name CoCoTANG
run all
