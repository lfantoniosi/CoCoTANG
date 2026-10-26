Hardware-confirmed CVBS baseline with #7 enabled

The user confirmed the video-only CVBS baseline and then the #7 phase-aligned
image on 2026-10-26. The exact current image is impl/pnr/stable-cvbs.fs, with
its timing report, source archive and SHA256 manifest. The previous working
phase-alignment-off baseline remains in impl/pnr/stable-cvbs-before-phase7*.
The RGB configuration remains identical to rgb-accuracy-d.fs.

CoCoTANG-cvbs-minimal.gprj substitutes exactly two files:
  src/cvbs/minimal_top_coco3.v
  src/cvbs/video/coco_cvbs_ntsc_lut.v
Every other source, including CPU bus capture, SDRAM, SSC, IDE, GIME and HDMI,
is unchanged from the original shared project. Normal RGB, PAL and component
projects compile no files from this directory. Placement settings are unchanged.

The encoder uses horizontal/read counters and exact RGB222 conversion lookup
tables. Composite smoothing, notch and chroma filters are disabled. #7 captures
the DDS half-turn bit at the NTSC field origin and corrects composite picture
chroma and burst. The DDS and S-Video Y/C remain continuous. The unfiltered
correction reuses quantized chroma plus its fractional remainder to preserve
rounding exactly, avoiding a duplicate matrix that failed routed timing.

Tests cover original S-Video waveform/raster identity, unfiltered composite
identity with alignment off, both phase states/all RGB222 colors, RGB/PAL
opt-out and real alternating 262/263-line field wraps. Scanline regressions
cover PMODE/artifact modes and patterned native graphics with scrolling.

Build: make rebuild-cvbs
Check timing: make timing-cvbs
Program existing image: make reprogram-cvbs
Regression tests: make test-cvbs
The ntsc-svideo targets use the same project/image. Preserve the project name,
source paths and output base CoCoTANG-cvbs-minimal to retain build identity.

Routed timing: clk108=108.074 MHz, clk135=136.898 MHz, clk270=301.752 MHz.
All clocks pass; setup/hold violations=0. The clock108 margin remains tight.
Keep the confirmed image/archive while evaluating subsequent changes.
Shared fixes must be reviewed for both implementations.

Rejected broader experiments remain archived in /private/tmp and impl/pnr.
They are absent from active projects/build targets. No SDRAM sampling, CPU
read-selector, CPU bus-retiming or SSC/IDE timing changes are included.
