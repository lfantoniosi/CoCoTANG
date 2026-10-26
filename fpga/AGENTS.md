# FPGA build settings

Preserve the placement settings used by the hardware-confirmed build. Do not
change FPGA placement options in the Gowin projects or `scripts/build.tcl`,
including as an attempted timing fix, unless the user explicitly requests it.

The confirmed RGB baseline uses `place_option 1`, `route_option 0`,
`replicate_resources 1`, and `route_maxfan 16`. Preserve these settings when
adding standalone test projects or changing Makefile targets. Keep changes to
other build settings separate from functional changes and describe them
explicitly to the user.

# CVBS isolation

The hardware-confirmed CVBS build uses `CoCoTANG-cvbs-minimal.gprj` with output
base `CoCoTANG-cvbs-minimal`. Preserve these names and the exact source paths:
`src/cvbs/minimal_top_coco3.v` and `src/cvbs/video/coco_cvbs_ntsc_lut.v`.
All other files come from the original RGB/shared project. Normal CVBS and
NTSC/S-Video targets must use this confirmed project; RGB must continue using
its original project and shared RTL, with no `src/cvbs/` files or dependencies.

Confirmed images are `impl/pnr/stable-cvbs.fs` and
`impl/pnr/rgb-accuracy-d.fs`. The user confirmed the CVBS video-only baseline
and then #7 composite-only field-phase alignment on 2026-10-26. #7 is enabled
in the active CVBS top. The previous confirmed image and exact sources remain
in `impl/pnr/stable-cvbs-before-phase7*` for rollback.

Keep the DDS and S-Video carrier continuous. The composite-only half-turn
correction reuses the existing chroma matrix with exact fractional rounding;
duplicating that matrix failed timing. Do not reintroduce the rejected SSC/IDE,
SDRAM-sampling or CPU bus-retiming experiments. Parameter-disabled shared
changes have disturbed RGB synthesis results; verify the approved RGB
configuration payload when changing this boundary.

# PAL isolation

PAL analog timing work uses CoCoTANG-pal-analog.gprj and only src/pal/ variants.
Do not modify CoCoTANG-pal.gprj: it remains the shared RGB/YPbPr project.
Keep src/pal/ out of other project file lists and common source dependencies.
The PAL-only build_options.json records the existing PAL options (place1,
route1, replication enabled, maxfan16); copying it to the PAL project's own
process config preserves settings rather than tuning placement. Do not
change these values to solve timing. RGB/CVBS sources and images must match
their confirmed baselines. PAL was hardware-confirmed on 2026-10-26 using
pal-narrow-phase-test.fs, saved with its exact source archive and timing as
impl/pnr/stable-pal*. Preserve the phase-selection and narrow signed-rounding
implementation, project identity and source paths of this confirmed build.

The user selected this confirmed version as the PAL baseline. Leave the PAL
carrier continuous; no additional frame/chroma phase alignment is authorized.
