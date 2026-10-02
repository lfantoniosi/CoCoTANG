# CoCoTANG FPGA

Tang Nano 20K implementation of the CoCo 3 memory, GIME video, storage, and
digital/analog output subsystem. The original MC6809E and motherboard PIAs
remain in the computer.

## Design

The default Makefile build uses the timing-qualified NTSC S-Video top-level.
The FPGA provides:

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
ROM load have completed. `roms/coco3.rom` is the 32 KiB CoCo 3 ROM image
stored in module flash at offset `0x100000`. Program it with:

```sh
make rom
```

For the experimental PAL-chroma variant, program the supplied 32 KiB
`coco3p.rom` from `/Users/felipe/src/retro/coco_roms/coco3p.rom` using
`make pal-rom`. The path can be overridden with `PAL_ROM=/path/to/coco3p.rom`.
The ROM is not copied into this repository. `make rom` restores the normal
ROM at the same flash offset.

## Video

`ANALOG_VIDEO_MODE=2` produces Y/Pb/Pr component video:
Y with sync on pin 56, Pb on pin 54, and Pr on pin 18. Values 0 and 1 use pin
54 for S-Video chroma and pin 18 for composite video. Pin 51 carries the 6809
E clock because the original E connection is shared with HSPI. Separate Y
uses the component HAT's seven-bit sigma-delta method: a 40-code sync-to-black
pedestal and an 87-code black-to-white excursion.

The default `ANALOG_VIDEO_MODE=1` selects the CVBS/S-Video HAT. Its NTSC
S-Video output uses the same DAC-generated burst and picture-to-burst phase
treatment as the experimental PAL path, but retains the NTSC colour carrier.
CVBS encoding is unchanged.

`ANALOG_VIDEO_MODE=3` reuses the component HAT for RGB
with sync on green:
pin 56/Y is green with composite sync, pin 54/Pb is blue, and pin 18/Pr is
red. The existing 1 kOhm/4.7 kOhm transistor inputs, 75-ohm output resistors,
and 470 pF output capacitors are retained. Measured CRT calibration uses
independent nonlinear transfer curves for red, green, and blue. Green includes
the 40-code pedestal required for negative composite sync.

HDMI uses sharp 640-dot native output. Compatibility modes retain the CoCo 3
GIME's MC6847-compatible character and artifact-color behavior.

The build uses NTSC-machine CPU and video timing. At runtime, VMODE `$FF98`
bit 3 (H50) selects 60- or 50-Hz vertical timing without changing the CPU
clock. The 50-Hz path retains NTSC-machine timing and colour encoding while
using a 625-line output raster. HDMI follows
H50 using 720x480p59.94 or 720x576p50 respectively.

### Experimental PAL-chroma variant

`make pal-rebuild` builds `impl/pnr/CoCoTANG-pal.fs`. To try it on hardware,
run `make pal-rom` and `make pal-program`. This variant selects the existing
CVBS/S-Video analog pins, generates a 4.43361875 MHz PAL chroma carrier, and
alternates the V chroma component and burst phase on successive scanlines.
It does **not** change the NTSC-derived CPU E/Q or video clocks, horizontal
timing, or GIME raster. Thus it is PAL-colour encoding on the existing CoCo
timing, not a standards-compliant PAL computer or guaranteed-compatible
625/50 signal. HDMI is unchanged. Use `make rom` and `make program` to restore
the standard ROM and default NTSC CVBS/S-Video bitstream.

The matched NTSC S-Video path is also available as explicitly named
`make ntsc-svideo-rebuild`/`make ntsc-svideo-program` targets. The default
`make build`, `make rebuild`, `make timing`, and `make program` use that same
timing-qualified S-Video top-level.
Neither bitstream replaces the ROM in SPI flash: leave `coco3p.rom` installed
for a direct PAL-versus-NTSC carrier comparison, or run `make rom` if you also
want the normal NTSC ROM. The separate `ANALOG_VIDEO_MODE=3` RGB configuration
is unchanged.

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
make program    # build if needed and program the FPGA flash
make reprogram  # program the existing bitstream
```

The default generated bitstream is `impl/pnr/CoCoTANG-ntsc-svideo.fs`. See
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
