# CoCoTANG FPGA

Tang Nano 20K replacement for the CoCo 2/3 memory/video subsystem. The
external 6809 and PIAs remain in the CoCo.

## Machine configuration

Top parameter `COCO_MODEL` selects the machine-specific core. Model `2` is
implemented under `src/coco2/` and contains the SAM and MC6847 core/wrapper.
Model `3` is under `src/coco3/` and contains GIME CPU timing, register/MMU
decoding, and the video renderer. The current bring-up default is model 2.

Clock generation, physical CPU-bus multiplexing, startup, SDRAM/ROM access,
framebuffer, HDMI, and analog video encoding are common top-level services.
Both machine cores use the same bus, video-memory, and framebuffer interface.

## Startup and memory

The CPU HALT transistor is driven until both PLLs lock, the embedded SDRAM has
completed two initialization passes, and the selected ROM image has been
copied from SPI flash. Program the image at flash offset `0x100000` with
`make coco2_rom` or `make coco3_rom`. The CoCo 2 image layout is:

| Image offset | CoCo selection | CoCo address |
|---:|---|---:|
| `0x0000-0x1fff` | BASIC | `$A000-$BFFF` and vectors |
| `0x2000-0x3fff` | Extended BASIC | `$8000-$9FFF` |

CoCo 2 RAM uses SDRAM byte addresses `0x000000-0x00ffff`; CoCo 3 physical RAM
uses its full 19-bit `0x000000-0x07ffff` range. The ROM cache is kept outside
that range at `0x080000-0x087fff`. The loader copies 16 KiB for model 2 or the
complete 32 KiB `roms/coco3.rom` image for model 3.

Top parameter `SDRAM_TEST_FILL` is currently `1` for standalone board testing.
Before loading the ROM, startup fills the complete 512 KiB GIME RAM range with
`RAM[address] = address[7:0]`; HALT remains asserted until both operations
finish. This gives the VDG a deterministic 0-to-255 character pattern. Set
the parameter to `0` for normal CoCo startup without the diagnostic fill.

## Video

The MC6847-compatible renderer is based on the MiSTer CoCo 2 implementation.
SAM writes at `$FFC0-$FFC5` latch the three graphics mode bits internally.
PIA1 port-B writes are shadowed for A/G, INT/EXT, and CSS. A 256x192 frame
buffer feeds 720x480 DVI-compatible HDMI. Top-level parameter
`ANALOG_VIDEO_MODE` selects the signal on the second one-bit analog output:
`0` generates S-Video chroma on Pb; the default `1` generates composite video
on Pb. Y always generates luma. The former Pr output is repurposed as the 6809
E clock because the original E pin is shared with the module's HSPI interface.
Both analog modes use the calibrated NTSCVideo format: a 13.5 MHz
858x262 sample grid, NTSC equalizing/broad sync, 227.5 color-carrier cycles
per line, levels 0/10/32 for sync/blank/white, and a 270 MHz sigma-delta DAC.

The first-stage GIME renderer implements `$FF90/$FF91`, `$FF98-$FF9F`, the
16 MMU registers, 16 palette registers, 19-bit screen addressing, text/color
attributes, 2/4/16-color graphics, and the 192-, 199-, and 225-visible-line
modes. All source widths are scaled into a 256x225 RGB222 framebuffer and
centered independently by HDMI and CVBS. Set `DEBUG_S2_VIDEO_MODE=1` only for
the legacy video-mode walker; it is disabled in normal builds. Compatibility-mode VDG,
interrupt/timer behavior, blinking/underline, and the complete CoCo 3 font
remain for the next GIME pass.

The shared framebuffer uses one physical write port and time-multiplexes its
135 MHz read port between HDMI and CVBS. Explicit 32K banks allow the full
225-line image to infer as BSRAM without duplicating the framebuffer.

For CoCo 2 board bring-up, `DEBUG_HDMI_OVERLAY=1` adds a framebuffer-independent
full-screen 90x60-character bus log. It captures the first 464 CPU cycles after
reset, displays them oldest-first as four 116-cycle pages in two columns, and
then freezes. Each
entry shows direction, address, physical bus data (`DI`), FPGA memory data
(`DO`), output enable, and SAM select. `DO:--` means the FPGA did not drive that
cycle, as expected for writes and motherboard I/O reads. A short S2 press moves
to the next page; holding S2 for about one second toggles the overlay off or on.
It starts visible after FPGA reset. CPU memory traffic is suppressed
until startup is complete and while CPU reset or halt is asserted. Set
`DEBUG_HDMI_OVERLAY=0` to remove the logger entirely.

## Build

Run `make` with Gowin EDA installed. `make program` builds and programs the
FPGA; `make coco2_rom` or `make coco3_rom` programs only the selected ROM
payload. `make test` runs the SAM, GIME, framebuffer, CVBS, SDRAM-fill, and
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
