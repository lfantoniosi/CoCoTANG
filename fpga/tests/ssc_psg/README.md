# SSC sound and speech test disk

Build with `make ssc-psg-dsk`. Mount `results/SSCPSG.DSK`, then run
`RUN "PSGTEST"` or `RUN "PSGAUTO"`.

`PSGTEST.BAS` adapts the direct-register channel-A example from printed page
25 of the [Tandy Speech/Sound Cartridge owner's manual](https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Speech-Sound%20Cartridge%20%28Tandy%29.pdf).
It uses the same reset, PIA audio selection, busy handshake, AF command,
and register writes, with reusable byte/register helpers, input validation,
a busy timeout, and an explicit stop command. Enter 254 for approximately
440 Hz, or 0 to stop and silence the PSG.

`PSGAUTO.BAS` is an additional test: it plays A, B, C separately and then
a three-voice chord. Each step lasts about two seconds at 60 Hz. The mono
PSG is mixed into both HDMI channels and the physical audio output, alongside
the existing PIA and Orchestra-90 sources. Speech is mixed into the same outputs. The shared SSC mix uses unity gain
and saturates overloads.

`RUN "SPEAK"` says “Color Computer” using buffered AL2 allophones. Its phrase
is from the manual's printed page 14 example. It loads buffer 0 with B0,
ends the stream with a pause and FF, executes with F0, and waits for
status bit 6 to return high after the final allophone finishes.
`RUN "SSCDETEC"` exercises Pitfall II's actual presence probe: space, CR,
then speech activity followed by idle. This silent phrase takes about 200 ms.

Implemented speech commands are A0–A7/B0–B7 (load chained/single allophone
buffers), E0–E7/F0–F7 (execute), C7 (abort), and 00 (stop everything).
Reset stops speech and sound without clearing the buffers. The 2.56-MHz
Speech256 enable produces 10-kHz samples within the 108-MHz clock domain.
The controller tracks playback beyond the final queued allophone.

`RUN "SPEAK2"` runs the supplied ASCII text-to-speech program unchanged.
Type an English sentence and press ENTER. `RUN "SAY"` provides the same
interface with initialization and `LINE INPUT`, so commas are accepted in
sentences. An empty line exits SAY.

The FPGA now translates ASCII English text to allophones using the public
[NRL letter-to-sound rules](../../src/third_party/nrl_tts/README.md). It handles
upper/lowercase, word context, punctuation and digits (spoken individually).
Speech starts after carriage return (13). A final pause silences the engine.
BUSY remains low during text playback; poll bit 7 before sending the next
byte, as SPEAK2 does. The normalized input buffer holds 510 characters,
including inserted word boundaries; excess text is discarded. The CoCo BASIC
input line normally fits comfortably within that limit. Reset or C7 aborts
text playback and clears the pending sentence.

Text-buffer commands 80–87/90–97/C0–C6/D0–D7 remain unsupported. Immediate
ASCII/CR and buffered explicit allophones are implemented. This is
command-level compatibility using NRL pronunciation rules; it is not a
TMS7040 CPU emulation and pronunciations may differ from the original SSC.
KQ1/KQ2's SSC-enabled Sierra loader expects BF shortly after reset; the 1-ms
speech-startup window reproduces that probe. All three game probes are
covered in simulation; gameplay still needs validation on the board.

SSC sound and speech default to enabled (`ENABLE_SSC_PSG=1` in `src/top_coco3.v`).
`ENABLE_SSC_SPEECH=0` keeps the PSG while removing the speech core.
For RGB, build with `make build-rgb`, check `make timing-rgb`, then flash
with `make reprogram-rgb`. The YPbPr and CVBS targets include the same audio
support. Setting `ENABLE_SSC_PSG=0` removes both SSC synthesizers and bypasses their mixer.

The host writes reset 1 then 0 to `$FF7D`. `$FF7E` is the command/data write
port and status read port; bit 7 high means ready. This does not overlap
Orchestra-90's `$FF7A`/`$FF7B` DACs.
