create_clock -name clkin -period 37.037 [get_ports {clkin}] -add
set_max_delay 20.000 -from [get_clocks {clkin}] -to [get_ports {cpu_data[*] e_out q_out}]
create_clock -name clk108 -period 9.259 [get_pins {display_enabled.clocks/sdram_pll/rpll_inst/CLKOUT}] -add
create_clock -name clk135 -period 7.407 [get_nets {display_enabled.clk135}] -add
create_clock -name pixel_clk -period 37.037 [get_nets {display_enabled.pixel_clk}] -add
set_clock_groups -asynchronous -group [get_clocks {clkin}] -group [get_clocks {clk108}] -group [get_clocks {clk135 pixel_clk}]
