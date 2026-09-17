# CoCoTANG FPGA

Tang Nano 20K replacement for the CoCo 2 memory/video subsystem. The
external 6809 and PIAs remain in the CoCo.

## Machine configuration

The root `CoCoTANG.gprj` is the hardware-verified CoCo 2 design. It combines
the physical CPU-bus interface with SAM timing, SDRAM/ROM service, the MC6847
renderer, line-buffered HDMI, and streaming composite video. Experimental
CoCo 3 sources remain under `src/coco3/`, but are not part of the main build.

## Startup and memory

The CPU HALT transistor is driven until both PLLs lock, the embedded SDRAM has
completed two initialization passes, and the selected ROM image has been
copied from SPI flash. Program the image at flash offset `0x100000` with
`make coco2_rom`. The image layout is:

| Image offset | CoCo selection | CoCo address |
|---:|---|---:|
| `0x0000-0x1fff` | BASIC | `$A000-$BFFF` and vectors |
| `0x2000-0x3fff` | Extended BASIC | `$8000-$9FFF` |

RAM uses SDRAM byte addresses `0x000000-0x00ffff`. The 16 KiB ROM image is
loaded at SDRAM byte address `0x080000` before the physical CPU is released.

## Video

The MC6847-compatible renderer is based on the MiSTer CoCo 2 implementation.
SAM writes at `$FFC0-$FFC5` latch the display-address mode internally. PIA1
port-B writes are shadowed from CPU start for A/G, GM2-GM0, INT/EXT, and CSS;
the shadow remains active while video timing waits for an HDMI frame boundary.
The separate controls distinguish modes sharing one SAM memory geometry,
including PMODE 3 (128x192 four-color) and PMODE 4 (256x192 two-color).
Alternating line
buffers bridge the scan-doubled VDG stream into 720x480 DVI-compatible HDMI;
there is no full-frame buffer. Top-level parameter
`ANALOG_VIDEO_MODE` selects the signal on the second one-bit analog output:
`0` generates S-Video chroma on Pb; the default `1` generates composite video
on Pb. Y always generates luma. The former Pr output is repurposed as the 6809
E clock because the original E pin is shared with the module's HSPI interface.
Both analog modes use the calibrated NTSCVideo format: a 13.5 MHz
858x262 sample grid, NTSC equalizing/broad sync, 227.5 color-carrier cycles
per line, levels 0/10/32 for sync/blank/white, and a 270 MHz sigma-delta DAC.

For board diagnostics, `ENABLE_BUS_LOGGER=1` and `DEBUG_OVERLAY=1` add a
full-screen 90x60-character bus log. It captures the first 464 CPU cycles after
reset, displays them oldest-first as four 116-cycle pages in two columns, and
then freezes. Each
entry shows direction, address, physical bus data (`DI`), FPGA memory data
(`DO`), output enable, and SAM select. `DO:--` means the FPGA did not drive that
cycle, as expected for writes and motherboard I/O reads. A short S2 press moves
to the next page; holding S2 for about one second toggles the overlay off or on.
It starts visible after FPGA reset. CPU memory traffic is suppressed
until startup is complete and while CPU reset or halt is asserted. Set
both parameters to `0` to remove the logger entirely.

## Build

Run `make` with Gowin EDA installed. `make program` builds and programs the
FPGA; `make coco2_rom` programs only the ROM payload. `make test` runs the
SAM, retained GIME unit tests, framebuffer, CVBS, SDRAM-fill, and
multiplexed-bus simulations. See
[`docs/pinout.md`](docs/pinout.md) for the FPGA pin and 74HC139 scan map.

The low-level SDRAM, SPI flash reader, and HDMI encoder/serializer are adapted
from [new-juice](https://github.com/lfantoniosi/new-juice). The MC6847 renderer
and character data are adapted from
[MiSTer CoCo2](https://github.com/MiSTer-devel/CoCo2_MiSTer).
The initial GIME register/mode behavior was checked against the local
`Lomont_CoCoHardware.pdf` and the
[MiSTer CoCo3 core](https://github.com/MiSTer-devel/CoCo3_MiSTer).

Note: the local KiCad Tang Nano symbol labels the Q header contact as FPGA pin
78. The official Tang Nano 20K pinout and Gowin QN88 package database both use
pin 76; `top.cst` uses 76. The schematic symbol should be corrected before the
next PCB revision.
