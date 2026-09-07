if {![info exists ::env(COCOTANG_FPGA_ROOT)]} {
    error "COCOTANG_FPGA_ROOT is not set"
}
cd $::env(COCOTANG_FPGA_ROOT)
open_project [file join $::env(COCOTANG_FPGA_ROOT) CoCoTANG.gprj]
run all
