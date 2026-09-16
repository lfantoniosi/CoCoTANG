create_clock -name clkin -period 37.037 [get_ports {clkin}] -add
create_clock -name clk108 -period 9.259 [get_nets {clk108}] -add
create_clock -name clk270 -period 3.704 [get_nets {clk270}] -add
create_clock -name clk135 -period 7.407 [get_nets {clk135}] -add
create_clock -name clk27 -period 37.037 [get_nets {clk27}] -add
set_false_path -from [get_ports {s1 s2 mp[*] irq_n_in firq_n_in audio_in cpu_data[*]}]
set_clock_groups -asynchronous -group [get_clocks {clkin clk27 clk135 clk270}] -group [get_clocks {clk108}]
