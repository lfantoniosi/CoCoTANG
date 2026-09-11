if {![info exists ::env(COCOTANG_FPGA_ROOT)]} {
    error "COCOTANG_FPGA_ROOT is not set"
}
cd [file join $::env(COCOTANG_FPGA_ROOT) cpu_test]
open_project [file join $::env(COCOTANG_FPGA_ROOT) cpu_test CoCoTANG_cpu_test.gprj]
set_option -top_module top_cpu_test
set_option -output_base_name CoCoTANG_cpu_test
run all
