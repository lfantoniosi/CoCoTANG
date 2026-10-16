#!/usr/bin/env python3
"""Run the top-level SSC toggle test with the installed Gowin primitives."""
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
primitives = Path(sys.argv[1])
sources = [
    entry.attrib['path']
    for entry in ET.parse(root / 'CoCoTANG.gprj').findall('.//File')
    if entry.attrib['path'].endswith(('.v', '.sv'))
    and '/hdmi/' not in entry.attrib['path']
]
# Stub the HDMI encoder/serializer; exercise the real SSC, speech and bus logic.
with tempfile.TemporaryDirectory(prefix='cocotang-ssc-toggle-') as directory:
    output = Path(directory) / 'simulation'
    for analog_banner in (1, 0):
        subprocess.run([
            'iverilog', '-g2012', '-DCOCOTANG_GOWIN_SIMLIB',
            '-s', 'tb_cocotang_ssc_toggle',
            f'-Ptb_cocotang_ssc_toggle.ENABLE_ANALOG_BANNER={analog_banner}',
            '-o', str(output),
            'tests/tb_cocotang_ssc_toggle.sv',
            'tests/tb_coco3_hdmi_border_handoff.sv',
            *sources, str(primitives),
        ], cwd=root, check=True)
        subprocess.run(['vvp', str(output)], cwd=root, check=True)
