# CoCoTANG FPGA

Tang Nano 20K replacement for the CoCo 2 SAM, 64 KiB RAM, BASIC/Extended
BASIC ROMs, and MC6847 VDG. The external 6809 and PIAs remain in the CoCo.

## Startup and memory

The CPU HALT transistor is driven until both PLLs lock, the embedded SDRAM has
completed two initialization passes, and the 16 KiB ROM image has been copied
from SPI flash. Program `roms/coco2.rom` at flash offset `0x100000` with
`make roms`. Its layout is:

| Image offset | CoCo selection | CoCo address |
|---:|---|---:|
| `0x0000-0x1fff` | BASIC | `$A000-$BFFF` and vectors |
| `0x2000-0x3fff` | Extended BASIC | `$8000-$9FFF` |

RAM uses SDRAM byte addresses `0x000000-0x00ffff`; the ROM cache uses
`0x010000-0x013fff`. SAM `$FFDE/$FFDF` selects ROM/RAM or all-RAM mode.

Top parameter `SDRAM_TEST_FILL` is currently `1` for standalone board testing.
Before loading the ROM, startup fills the first 64 KiB with
`RAM[address] = address[7:0]`; HALT remains asserted until both operations
finish. This gives the VDG a deterministic 0-to-255 character pattern. Set
the parameter to `0` for normal CoCo startup without the diagnostic fill.

## Video

The MC6847-compatible renderer is based on the MiSTer CoCo 2 implementation.
SAM writes at `$FFC0-$FFC5` latch the three graphics mode bits internally.
PIA1 port-B writes are shadowed for A/G, INT/EXT, and CSS. A 256x192 frame
buffer feeds 720x480 DVI-compatible HDMI. Top-level parameter
`ANALOG_VIDEO_MODE` selects the three one-bit analog outputs: `0` generates
Y/Pb/Pr component video; the default `1` generates luma on Y, S-Video chroma
on Pb, and composite video on Pr (the pin-32 CVBS transistor circuit).
The S-Video/CVBS mode uses the calibrated NTSCVideo format: a 13.5 MHz
858x262 sample grid, NTSC equalizing/broad sync, 227.5 color-carrier cycles
per line, levels 0/10/32 for sync/blank/white, and a 270 MHz sigma-delta DAC.

## Build

Run `make` with Gowin EDA installed. `make program` builds and programs the
FPGA; `make roms` programs only the CoCo 2 ROM payload. `make test` runs the
SAM timing/register and multiplexed-bus simulations. See
[`docs/pinout.md`](docs/pinout.md) for the FPGA pin and 74HC139 scan map.

The low-level SDRAM, SPI flash reader, and HDMI encoder/serializer are adapted
from [new-juice](https://github.com/lfantoniosi/new-juice). The MC6847 renderer
and character data are adapted from
[MiSTer CoCo2](https://github.com/MiSTer-devel/CoCo2_MiSTer).

Note: the local KiCad Tang Nano symbol labels the Q header contact as FPGA pin
78. The official Tang Nano 20K pinout and Gowin QN88 package database both use
pin 76; `top.cst` uses 76. The schematic symbol should be corrected before the
next PCB revision.
