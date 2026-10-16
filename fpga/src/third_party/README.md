# SSC audio cores

`jt49/` is [JT49](https://github.com/jotego/jt49), commit
`47301ed51374d6d41db4db846b7643fecf75e417`, by Jose Tejada Gomez.
It is licensed under GPLv3 or later. The upstream license and source headers
are retained. `ENABLE_SSC_PSG` controls inclusion of this core.

Speech uses [Speech256](https://github.com/trcwm/Speech256), commit
`4c311cfa90790761feceecc5440a2981040c89cd`, in `ssc_speech/`.
Its source headers specify GPLv3 or later; the upstream LICENSE says LGPLv3.
Both notices and COPYING-GPL3 are retained; assume GPLv3 for these files.
The encoded allophone ROM is included upstream. Local changes add a synchronous
clock enable, expose the final allophone's completion, infer the ROM as memory,
provide a coefficient default, and use blocking combinational assignments.
The SSC interface and PSG are enabled by `ENABLE_SSC_PSG` in the top level.
`ENABLE_SSC_SPEECH` independently removes the speech synthesizer.

`nrl_tts/` contains the public English pronunciation data used by the ASCII
text-to-speech translator. See its README and Unlicense for provenance.
