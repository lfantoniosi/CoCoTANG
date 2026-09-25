# CoCoTANG FPGA

Tang Nano 20K implementation of the CoCo 3 memory, GIME video, storage, and
digital/analog output subsystem. The original MC6809E and motherboard PIAs
remain in the computer.

## Design

`CoCoTANG.gprj` builds `top_coco3`. The FPGA provides:

- GIME-compatible CPU timing, MMU, interrupts, palette, native graphics, and
  legacy compatibility video modes.
- 512 KiB base memory with the optional Disto 2 MiB mapping enabled by
  default.
- A 32 KiB ROM loaded from module SPI flash into dedicated block RAM.
- Scanline-buffered HDMI and NTSC-rate component, S-Video, or composite
  output without a full-frame buffer.
- A Glenside-compatible IDE interface backed by the module's TF card in SPI
  mode.

## ROM and memory

At startup the CPU remains halted until the clocks, SDRAM initialization, and
ROM load have completed. `roms/coco3.rom` and `roms/coco3p.rom` are the 32 KiB
NTSC and PAL CoCo 3 ROM images stored in module flash at offset `0x100000`.
Program the ROM matching the machine-standard bitstream with:

```sh
make rom
make pal-rom
```

## Video

`ANALOG_VIDEO_MODE=2` is the default and produces Y/Pb/Pr component video:
Y with sync on pin 56, Pb on pin 54, and Pr on pin 18. Values 0 and 1 use pin
54 for S-Video chroma and pin 18 for composite video. Pin 51 carries the 6809
E clock because the original E connection is shared with HSPI.

HDMI can use sharp 640-dot native output (`NATIVE_HDMI_640=1`) or an
aspect-correct 512-dot filtered image. Compatibility modes retain the CoCo 3
GIME's MC6847-compatible character and artifact-color behavior.

`PAL_MACHINE` is the fixed motherboard-standard build flag in `top_coco3`.
The normal targets leave it at `0` for the 28.63636 MHz NTSC machine. The
`pal-build`/`pal-rebuild` targets use `CoCoTANG_PAL.gprj`, which fixes it at
`1` for the 28.475 MHz PAL machine. This flag selects the crystal-derived E/Q timing and immutable
analogue colour family. At runtime, VMODE `$FF98` bit 3 (H50) selects 60- or
50-Hz vertical timing without changing those machine clocks. HDMI follows
H50 using 720x480p59.94 or 720x576p50 respectively.

## Glenside IDE / TF card

The default task-file occupies `$FF50-$FF57`, with the Glenside high-byte
latch at `$FF58`. The implementation supports LBA28 `READ SECTORS`, `WRITE
SECTORS`, `IDENTIFY DEVICE`, and `EXECUTE DEVICE DIAGNOSTIC`.

The TF card uses SD SPI mode:

- `SD_CLK`: SCLK
- `SD_CMD`: MOSI
- `SD_DAT0`: MISO
- `SD_DAT3`: active-low chip select

Initialization runs at 400 kHz and block transfers at 1 MHz. Every read block
is CRC16-verified and every write carries a calculated CRC16. SD, SDHC, and
SDXC addressing is supported.

## Build and test

With Gowin EDA and `openFPGALoader` installed:

```sh
make test       # RTL regression suite
make rebuild    # clean synthesis, place-and-route, and bitstream
make pal-rebuild # same for a PAL motherboard; produces CoCoTANG_PAL.fs
make program    # build if needed and program SRAM
make pal-program # build/program the PAL-machine bitstream
make reprogram  # program the existing bitstream
```

The generated bitstream is `impl/pnr/CoCoTANG.fs`. See
[`docs/pinout.md`](docs/pinout.md) for the FPGA pin and bus-multiplexer map.

Low-level SDRAM, SPI flash, and HDMI code was adapted from
[new-juice](https://github.com/lfantoniosi/new-juice). GIME behavior and
character data were checked against `Lomont_CoCoHardware.pdf` and the
[MiSTer CoCo3 core](https://github.com/MiSTer-devel/CoCo3_MiSTer).

## Hardware note

The local KiCad Tang Nano symbol labels the Q header contact as FPGA pin 78.
The official Tang Nano 20K pinout and Gowin QN88 database use pin 76; the
CoCo 3 constraint file correctly uses pin 76. Correct the symbol before a PCB
respin.
