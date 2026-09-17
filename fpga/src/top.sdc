create_clock -name clkin -period 37.037 [get_ports {clkin}] -add
create_clock -name clk108 -period 9.259 [get_nets {clk108}] -add
create_clock -name clk270 -period 3.704 [get_nets {clk270}] -add
create_clock -name clk135 -period 7.407 [get_nets {clk135}] -add
create_clock -name clk27 -period 37.037 [get_nets {clk27}] -add
set_false_path -from [get_ports {s1 s2 mp[*] irq_n_in firq_n_in audio_in cpu_data[*]}]
set_clock_groups -asynchronous -group [get_clocks {clkin clk27 clk135 clk270}] -group [get_clocks {clk108}]

# These outputs clock and select real motherboard devices.  They were
# previously unconstrained, so harmless RTL changes could move their fabric
# registers/routes and change physical CPU-bus timing without an STA failure.
# Bound clock-to-pin delay explicitly; CPU data itself is already registered
# in the I/O cells by top.v.
set_max_delay 10.000 -from [get_clocks {clk108}] -to [get_ports {e_out q_out}]
set_max_delay 14.000 -from [get_clocks {clk135}] -to [get_ports {sam_s[*]}]
set_max_delay 9.000 -from [get_clocks {clk135}] -to [get_ports {msel[*]}]
