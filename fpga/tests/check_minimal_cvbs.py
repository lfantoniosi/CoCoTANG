"""Verify the video-only CVBS boundary and compare against shared RTL."""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def project_files(name):
    return [node.attrib['path'] for node in
            ET.parse(ROOT / name).getroot().findall('./FileList/File')]


def main():
    changes = {'src/top_coco3.v': 'src/cvbs/minimal_top_coco3.v',
               'src/video/coco_cvbs_ntsc.v': 'src/cvbs/video/coco_cvbs_ntsc_lut.v'}
    base = project_files('CoCoTANG-pal.gprj')
    assert project_files('CoCoTANG-cvbs-minimal.gprj') == [changes.get(name, name) for name in base]
    for project in ('CoCoTANG.gprj', 'CoCoTANG-pal.gprj'):
        assert not any(name.startswith('src/cvbs/') for name in project_files(project))
    original = (ROOT / 'src/top_coco3.v').read_text()
    minimal = (ROOT / 'src/cvbs/minimal_top_coco3.v').read_text()
    boundary = '    wire analog_luma,analog_chroma,analog_cvbs;'
    original_prefix = original.split(boundary)[0]
    minimal_prefix = minimal.split(boundary)[0].replace('    wire [9:0] cvbs_source_read_address_raw;\n', '')
    assert original_prefix == minimal_prefix, 'CPU/SDRAM/SSC/IDE/GIME/HDMI section changed'
    for flag in ('CVBS_LUMA_FILTER', 'CVBS_LUMA_NOTCH', 'CVBS_CHROMA_FILTER'):
        assert f'.{flag}(0)' in minimal
    assert '.CVBS_INCREMENTAL_DOTS(1)' in minimal
    assert '.CVBS_FIELD_PHASE_ALIGN(1)' in minimal
    assert 'CVBS_FAST_PREFETCH' not in minimal
    print('Minimal CVBS isolation PASS: exactly two source substitutions; shared interfaces unchanged', flush=True)
    with tempfile.TemporaryDirectory(prefix='cocotang-minimal-cvbs-') as directory:
        reference = Path(directory) / 'reference.v'
        encoder = (ROOT / 'src/video/coco_cvbs_ntsc.v').read_text()
        assert 'module coco_cvbs_ntsc #(' in encoder
        reference.write_text(encoder.replace('module coco_cvbs_ntsc #(', 'module coco_cvbs_ntsc_reference #(', 1))
        for filters in (1, 0):
            binary = Path(directory) / f'waveform-{filters}'
            subprocess.run(['iverilog', '-g2012', '-s', 'tb_cvbs_minimal',
                            f'-Ptb_cvbs_minimal.REFERENCE_FILTERS={filters}', '-o', str(binary),
                            'tests/tb_cvbs_minimal.sv', changes['src/video/coco_cvbs_ntsc.v'],
                            str(reference)], cwd=ROOT, check=True)
            subprocess.run(['vvp', str(binary)], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
