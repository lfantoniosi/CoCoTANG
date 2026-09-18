create_clock -name clkin -period 37.037 [get_ports {clkin}] -add
create_clock -name clk108 -period 9.259 [get_nets {clk108}] -add
//create_c ilock -name clk108p -period 9.259 -waveform {4.6295 9.259} [get_pins {clocks/sdram_pll/rpll_inst/CLKOUTP}] -add
create_clock -name clk270 -period 3.704 [get_nets {clk270}] -add
create_clock -name clk135 -period 7.407 [get_nets {clk135}] -add
create_clock -name clk27 -period 37.037 [get_nets {clk27}] -add
#set_false_path -from [get_ports {s1 s2 mp[*] audio_in cpu_data[*]}]
set_clock_groups -asynchronous -group [get_clocks {clkin clk27 clk135 clk270}] -group [get_clocks {clk108}]
set_max_delay 11.000 -from [get_clocks {clk108}] -to [get_ports {e_out q_out}]
## The mux scanner intentionally holds each MSEL bank for eight 270 MHz clocks.
## These constraints cover FPGA clock-to-pad delay while retaining more than
## 20 ns of external 74HC139/LVC245 settling time per bank.
set_max_delay 18.000 -from [get_clocks {clk108 clk270}] -to [get_ports {sam_s[*]}]
set_max_delay 10.000 -from [get_clocks {clk270}] -to [get_ports {msel[*]}]
