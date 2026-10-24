# CoCoTANG FPGA pin map

Package pins are for the GW2AR-LV18QN88C8/I7 on the Tang Nano 20K.

| FPGA signal | Direction | Package pin(s) | Board function |
|---|---|---:|---|
| `clkin` | in | 4 | 27 MHz module clock |
| `mp[7:0]` | in | 31, 30, 29, 26, 25, 28, 27, 77 | Multiplexed address/control bus |
| `msel[1:0]` | out | 20, 17 | 74HC139 mux selection |
| `cpu_data[7:0]` | inout | 48, 49, 86, 79, 72, 71, 53, 52 | Buffered 6809 data bus |
| `sam_s[2:0]` | out | 16, 41, 15 | SAM device selects to motherboard decoder |
| `e_out`, `q_out` | out | 51, 76 | 6809 clocks; E uses the PR_33 connection |
| `reset_drive` | out | 42 | High turns Q2 on and pulls `/RESET` low |
| `irq_n_in`, `firq_n_in` | out | 19, 75 | Active-high transistor drives for active-low IRQ/FIRQ |
| `hs_n`, `fs_n` | out | 73, 74 | VDG horizontal/field sync |
| `y_out`, `pb_out`, `cvbs_out` | out | 56, 54, 18 | RGB green/SoG, blue, and red (default mode) |
| `audio_out` | out | 55 | Sigma-delta CoCo DAC audio to the board's filtered line output |
| `mspi_sclk`, `mspi_cs`, `mspi_mosi`, `mspi_miso` | out/out/out/in | 59, 60, 61, 62 | On-module SPI flash |
| `sd_sclk`, `sd_cmd`, `sd_dat[0:3]` | out/inout/inout | 83, 82, 84, 85, 80, 81 | On-module TF card in SPI mode: CMD=MOSI, DAT0=MISO, DAT3=CS |
| `tmds_clk_p` | differential out | 33/34 | HDMI clock pair |
| `tmds_data_p[0]` | differential out | 35/36 | HDMI data 0 pair |
| `tmds_data_p[1]` | differential out | 37/38 | HDMI data 1 pair |
| `tmds_data_p[2]` | differential out | 39/40 | HDMI data 2 pair |
| `s1`, `s2` | in | 88, 87 | Module buttons; S1 resets, S2 toggles HDMI debug |

In component mode (`ANALOG_VIDEO_MODE=2`), `y_out` is Y/luma with sync,
`pb_out` is Pb, and `cvbs_out` is Pr. Legacy mode restores S-Video chroma and
independent composite on the
last two pins. Package pin 51 carries the 6809 E clock and package pin
75/`HSPI_DIR` drives the FIRQ transistor.

With the default `ANALOG_VIDEO_MODE=3`, the same component-HAT outputs become
green with composite sync, blue, and red respectively.

## 74HC139 scan map

`msel` selects one of the three 74LVC245 bus transceivers through U3. The
FPGA allows two settling clocks after changing selection and requires two
equal samples before accepting a scan.

| `msel[1:0]` | Enabled buffer | `mp[7:0]` meaning |
|---:|---|---|
| `00` | U8 | `A7..A0` |
| `01` | U10 | `A12,A11,A10,A9,A8,A13,A14,A15` |
| `10` | U11 | `NMI,HALT,KEYINT,CART,SERNT,SLENB,RESET,R/W` |
| `11` | none | idle |

The data bus is enabled externally by the motherboard `/MRD` decode and U12
uses `R/W` for direction. CoCoTANG therefore drives data only for an FPGA
memory read. `sam_s` supplies the three SAM selection outputs used by the
motherboard 74LS138, including the ROM and Extended BASIC selections.

## Schematic correction

The current KiCad Tang Nano symbol labels the Q contact as package pin 78.
The official Tang Nano 20K pinout and Gowin QN88 device database identify it
as pin 76. The constraint uses pin 76; correct the symbol before a PCB respin.

## Standalone bus tester

For the prototype with FPGA pin 42 connected to CPU RESET, build the
standalone tester with `make data-test-build` and load it with
`make data-test-program`. Its separate constraints name pin 42 `reset_drive`
and keep RESET asserted throughout the test.

The tester sweeps data from `$00` through `$FF`, holding each value for about
1 ms, and advances S2–S0 every 0.5 seconds. It drives data for S codes 0–2
when the mux reports RESET low and R/W high, and releases data for codes 3–7.
HDMI shows the data output, FPGA input readback, all three mux banks,
decoded CPU address, control inputs, and output strobes. FPGA input readback
observes the FPGA side of the data transceiver; a logic analyzer on the CPU
side checks the complete external path.

S2 toggles run/hold. In hold mode, S1 advances the byte and S code by one;
in run mode, S1 restarts both sweeps at zero.

Use `make test-data-bus` for the engine and HDMI screen simulations,
`make data-test-rebuild` for a forced FPGA rebuild, and `make data-test-timing`
to check the routed clock report. The image is
`impl/pnr/CoCoTANG-data-test.fs`.
