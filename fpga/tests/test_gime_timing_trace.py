#!/usr/bin/env python3
"""Compare the debug clock variant against the unmodified normal RTL."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
original = (root / 'src/coco3/gime_timing.v').read_text()
assert original.count('module gime_timing (') == 1
with tempfile.TemporaryDirectory(prefix='cocotang-trace-timing-') as directory:
    directory = Path(directory)
    reference = directory / 'reference.v'
    reference.write_text(original.replace('module gime_timing (',
                                          'module gime_timing_reference ('))
    executable = directory / 'test'
    subprocess.run(['iverilog', '-g2012', '-s', 'tb_gime_timing_trace',
                    '-o', str(executable),
                    str(root / 'tests/tb_gime_timing_trace.sv'),
                    str(root / 'src/debug/gime_timing_trace.v'),
                    str(reference)], check=True)
    subprocess.run(['vvp', str(executable)], check=True)
