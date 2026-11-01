# FPGA build settings

Preserve the placement settings used by the hardware-confirmed build. Do not
change FPGA placement options in the Gowin projects or `scripts/build.tcl`,
including as an attempted timing fix, unless the user explicitly requests it.

The confirmed RGB baseline uses `place_option 1`, `route_option 0`,
`replicate_resources 1`, and `route_maxfan 16`. Preserve these settings when
adding standalone test projects or changing Makefile targets. Keep changes to
other build settings separate from functional changes and describe them
explicitly to the user.

# RGB baseline

The official RGB baseline was promoted on 2026-11-01 after the user confirmed
good video and Boink with `rgb-ypbpr-lut-test.fs`. It is preserved as
`impl/pnr/stable-rgb.fs`, with exact sources, timing, placement options and
manifest in `impl/pnr/stable-rgb-*`. The active shared RGB RTL implements this
YPbPr-base raster with a 336-bit inverse LUT recovering all 64 RGB222 colors
exactly, including artifact colors. Preserve the aligned color/sync pipeline,
calibrated DAC levels, alternating RGB DAC phases, mux settling/early address
publication and equivalent refresh schedule. RGB still uses
`CoCoTANG-pal.gprj`, `top_coco3_rgb`, and output `CoCoTANG-rgb`; no variant
source dependencies or build settings were added. Routed Fmax is 108.156 MHz
and 135.793 MHz, with zero setup/hold violations; 108 MHz slack is only 0.013 ns.
`impl/pnr/rgb-accuracy-d.fs` remains the previous confirmed RGB rollback image.
The earlier `stable-rgb.fs` and timing are retained as `stable-rgb-before-lut*`;
pre-promotion shared working sources are in `rgb-before-lut-promotion-source.tar.gz`.
The confirmed CVBS/PAL/YPbPr images and isolated source files remain unchanged.
Shared mux/arbiter RTL changed in this RGB promotion; do not assume rebuilding
other variants reproduces their confirmed payloads. Their exact source archives
remain the authority for reproducing those images.

# CVBS isolation

The hardware-confirmed CVBS build uses `CoCoTANG-cvbs-minimal.gprj` with output
base `CoCoTANG-cvbs-minimal`. Preserve these names and the exact source paths:
`src/cvbs/minimal_top_coco3.v` and `src/cvbs/video/coco_cvbs_ntsc_lut.v`.
All other files come from the original RGB/shared project. Normal CVBS and
NTSC/S-Video targets must use this confirmed project; RGB must continue using
its original project and shared RTL, with no `src/cvbs/` files or dependencies.

Confirmed images are `impl/pnr/stable-cvbs.fs` and
`impl/pnr/stable-rgb.fs`. The user confirmed the CVBS video-only baseline
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
Do not modify CoCoTANG-pal.gprj: it remains the shared RGB project.
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

# YPbPr isolation

YPbPr timing experiments use CoCoTANG-ypbpr-analog.gprj and src/ypbpr/ only.
Preserve the confirmed RGB/CVBS/PAL projects, source paths and payloads.
The isolated YPbPr process config preserves place1, route1, replication=true
and maxfan16 from the shared project's prior settings. Do not tune placement.
The user confirmed very stable colors and successful Boink with
ypbpr-factored-test.fs on 2026-10-26. It is preserved as impl/pnr/stable-ypbpr*
with exact sources, timing and placement options. Preserve this factored
component matrix, earlier DAC selection and component blanking alignment.
The earlier ypbpr-early-blank-test.fs crashed and is rejected.
