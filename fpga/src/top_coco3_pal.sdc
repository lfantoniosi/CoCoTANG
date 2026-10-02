create_clock -name clkin -period 37.037 [get_ports {clkin}] -add
create_clock -name clk108 -period 9.259 [get_nets {core/clk108}] -add
create_clock -name clk108p -period 9.259 -waveform {4.629 9.259} [get_ports {O_sdram_clk}] -add
create_clock -name clk270 -period 3.704 [get_nets {core/clk270}] -add
create_clock -name clk135 -period 7.407 [get_nets {core/clk135}] -add
create_clock -name clk27 -period 37.037 [get_nets {core/clk27}] -add
create_clock -name audio48k -period 20833.333 [get_nets {core/pia1_audio_clk}] -add
set_clock_groups -asynchronous -group [get_clocks {clkin clk27 clk135 clk270}] -group [get_clocks {clk108}] -group [get_clocks {audio48k}]
set_max_delay 11.000 -from [get_clocks {clk108}] -to [get_ports {e_out q_out}]
set_max_delay 18.000 -from [get_clocks {clk108 clk135}] -to [get_ports {sam_s[*]}]
set_max_delay 10.000 -from [get_clocks {clk135}] -to [get_ports {msel[*]}]
