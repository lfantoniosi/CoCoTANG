create_clock -name clkin -period 37.037 [get_ports {clkin}] -add
create_clock -name clk108 -period 9.259 [get_nets {clk108}] -add
# clk108p is the PLL-generated SDRAM clock; Gowin derives it from CLKOUTP.
create_clock -name clk108p -period 9.259 -waveform {4.629 9.259} [get_ports {O_sdram_clk}] -add
create_clock -name clk270 -period 3.704 [get_nets {clk270}] -add
create_clock -name clk135 -period 7.407 [get_nets {clk135}] -add
create_clock -name clk27 -period 37.037 [get_nets {clk27}] -add
create_clock -name audio48k -period 20833.333 [get_nets {pia1_audio_clk}] -add
# Keep external input paths visible.  The asynchronous MP bus is captured by
# input IDDRs and all later crossings use explicit synchronizers.
set_clock_groups -asynchronous -group [get_clocks {clkin clk27 clk135 clk270}] -group [get_clocks {clk108}] -group [get_clocks {audio48k}]
set_max_delay 11.000 -from [get_clocks {clk108}] -to [get_ports {e_out q_out}]
# The mux scanner holds each switched MSEL bank for about 44 ns at 135 MHz.
# These constraints retain ample external 74HC139/LVC245 settling time.
set_max_delay 18.000 -from [get_clocks {clk108 clk135}] -to [get_ports {sam_s[*]}]
set_max_delay 10.000 -from [get_clocks {clk135}] -to [get_ports {msel[*]}]
