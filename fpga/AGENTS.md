# FPGA build settings

Preserve the placement settings used by the hardware-confirmed build. Do not
change FPGA placement options in the Gowin projects or `scripts/build.tcl`,
including as an attempted timing fix, unless the user explicitly requests it.

The confirmed RGB baseline uses `place_option 1`, `route_option 0`,
`replicate_resources 1`, and `route_maxfan 16`. Preserve these settings when
adding standalone test projects or changing Makefile targets. Keep changes to
other build settings separate from functional changes and describe them
explicitly to the user.
