Hardware-confirmed YPbPr baseline

The user confirmed very stable colors and successful Boink on 2026-10-26.
The tested image is ypbpr-factored-test.fs, preserved as impl/pnr/stable-ypbpr.fs
with its exact source archive, manifest, timing report and placement options.

CoCoTANG-ypbpr-analog.gprj substitutes only the top and encoder in src/ypbpr/.
RGB, CVBS and PAL retain their confirmed projects and sources. Shared CPU,
SDRAM, SSC, IDE, GIME, IRQ and HDMI logic are unchanged.

The analog path uses counter-based coordinate/read-address generation and
exact RGB222 lookup conversion from the confirmed PAL implementation.
The component matrix is factored into four-input correction lookups and
two-input channel levels. Parts are registered in the existing encoder stage
and summed in the existing mod stage. All reachable component levels are
1..127, allowing exact seven-bit modular arithmetic without saturation.
Picture blanking and DAC carry selection occur one stage earlier, preserving
output latency, waveform bits and sigma-delta residue.

The project preserves the prior placement settings: place1, route1,
replication=true, maxfan16. No other builds load its process configuration.

Build: make rebuild-ypbpr
Timing: make timing-ypbpr
Tests: make test-ypbpr
Program current build: make program-ypbpr

All clocks pass: clk108=108.114, clk135=146.944, clk270=307.572 MHz.
Setup/hold violated endpoints=0. The clk108 margin remains narrow.
Tests compare component bits against the original encoder across both raster
standards, native/compatibility modes and 192/199/225-line geometry. They also
cover signed chroma arithmetic, both component DAC phase settings, resets,
sync restarts and 80000 abrupt level transitions.

To restore the saved image, flash and fully power-cycle the CoCo:
openFPGALoader -b tangnano20k -f impl/pnr/stable-ypbpr.fs

The preceding ypbpr-early-blank-test.fs passed timing but crashed in hardware;
it is rejected. Earlier isolated, lookup-only, early-select and joint-table
trials missed timing. A timing pass alone does not establish stability.
