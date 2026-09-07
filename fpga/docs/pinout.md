# CoCoTANG FPGA pin map

Package pins are for the GW2AR-LV18QN88C8/I7 on the Tang Nano 20K.

| FPGA signal | Direction | Package pin(s) | Board function |
|---|---|---:|---|
| `clkin` | in | 4 | 27 MHz module clock |
| `mp[7:0]` | in | 31, 30, 29, 26, 25, 28, 27, 77 | Multiplexed address/control bus |
| `msel[1:0]` | out | 20, 17 | 74HC139 mux selection |
| `cpu_data[7:0]` | inout | 48, 49, 86, 79, 72, 71, 53, 52 | Buffered 6809 data bus |
| `sam_s[2:0]` | out | 16, 81, 41 | SAM device selects to motherboard decoder |
| `e_out`, `q_out` | out | 75, 76 | 6809 clocks |
| `halt_drive` | out | 42 | High turns Q2 on and pulls `/HALT` low |
| `irq_n_in`, `firq_n_in` | in | 19, 18 | Interrupt observations |
| `hs_n`, `fs_n` | out | 73, 74 | VDG horizontal/field sync |
| `y_out`, `pb_out`, `pr_out` | out | 56, 54, 51 | Analog Y/Pb/Pr, or luma/chroma/CVBS |
| `audio_in` | in | 55 | Audio observation/reserved for HDMI audio |
| `mspi_sclk`, `mspi_cs`, `mspi_mosi`, `mspi_miso` | out/out/out/in | 59, 60, 61, 62 | On-module SPI flash |
| `tmds_clk_p` | differential out | 33/34 | HDMI clock pair |
| `tmds_data_p[0]` | differential out | 35/36 | HDMI data 0 pair |
| `tmds_data_p[1]` | differential out | 37/38 | HDMI data 1 pair |
| `tmds_data_p[2]` | differential out | 39/40 | HDMI data 2 pair |
| `s1`, `s2` | in | 88, 87 | Module buttons; S1 resets, S2 is reserved |

With the default `ANALOG_VIDEO_MODE=1`, `y_out` is S-Video luma, `pb_out` is
S-Video chroma, and `pr_out` is composite video for the pin-32 transistor/RCA
circuit. Set the top parameter to `0` for component Y/Pb/Pr instead.

## 74HC139 scan map

`msel` selects one of the three 74LVC245 bus transceivers through U3. The
FPGA allows two settling clocks after changing selection and requires two
equal samples before accepting a scan.

| `msel[1:0]` | Enabled buffer | `mp[7:0]` meaning |
|---:|---|---|
| `00` | U8 | `A7..A0` |
| `01` | U10 | `A13,A14,A15,A12,A11,A10,A9,A8` |
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
