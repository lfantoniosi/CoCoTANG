"""Verify YPbPr isolation, unchanged placement options and encoder waveforms."""
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def files(name):
    return [node.attrib['path'] for node in ET.parse(ROOT / name).getroot().findall('./FileList/File')]


def main():
    replacements = {'src/top_coco3.v': 'src/ypbpr/minimal_top_coco3.v',
                    'src/video/coco_cvbs_ntsc.v': 'src/ypbpr/video/coco_cvbs_ntsc_lut.v'}
    assert files('CoCoTANG-ypbpr-analog.gprj') == [replacements.get(name, name) for name in files('CoCoTANG-pal.gprj')]
    for project in ('CoCoTANG.gprj', 'CoCoTANG-pal.gprj', 'CoCoTANG-cvbs-minimal.gprj', 'CoCoTANG-pal-analog.gprj', 'CoCoTANG-data-test.gprj'):
        assert not any(name.startswith('src/ypbpr/') for name in files(project)), project
    original = (ROOT / 'src/top_coco3.v').read_text()
    ypbpr = (ROOT / replacements['src/top_coco3.v']).read_text()
    boundary = '    wire analog_luma,analog_chroma,analog_cvbs;'
    prefix = ypbpr.split(boundary)[0].replace('    wire [9:0] cvbs_source_read_address_raw;\n', '')
    assert prefix == original.split(boundary)[0], 'YPbPr changed CPU/memory/peripheral/HDMI logic'
    assert '.CVBS_FIELD_PHASE_ALIGN(0)' in ypbpr
    assert '.CVBS_INCREMENTAL_DOTS(1)' in ypbpr
    for feature in ('CVBS_LUMA_FILTER', 'CVBS_LUMA_NOTCH', 'CVBS_CHROMA_FILTER'):
        assert f'.{feature}(0)' in ypbpr
    config = json.loads((ROOT / 'src/ypbpr/build_options.json').read_text())
    assert {key: config[key] for key in ('Place_Option', 'Route_Option', 'Replicate_Resources', 'Route_Maxfan')} == {
        'Place_Option': '1', 'Route_Option': '1', 'Replicate_Resources': True, 'Route_Maxfan': 16}
    for target, project in (('rebuild-ypbpr', 'CoCoTANG-ypbpr-analog.gprj'),
                            ('rebuild-rgb', 'CoCoTANG-pal.gprj'),
                            ('rebuild-cvbs', 'CoCoTANG-cvbs-minimal.gprj')):
        command = subprocess.check_output(['make', '-n', target], cwd=ROOT, text=True)
        assert f'COCOTANG_PROJECT="{project}"' in command, target
    print('YPbPr isolation PASS: two substitutions; shared CPU logic and other builds preserved; original YPbPr options', flush=True)
    with tempfile.TemporaryDirectory(prefix='cocotang-ypbpr-tests-') as directory:
        reference = Path(directory) / 'reference.v'
        reference.write_text((ROOT / 'src/video/coco_cvbs_ntsc.v').read_text().replace(
            'module coco_cvbs_ntsc #(', 'module coco_cvbs_ntsc_reference #(', 1))
        # Exhaust all signed operand values and phases. In particular, preserve
        # fractional rounding and the -1024 eleven-bit negate overflow.
        def chroma_function(source, name):
            start = source.index('    function signed [5:0] rgb_chroma;')
            end = source.index('    endfunction', start) + len('    endfunction')
            return source[start:end].replace('rgb_chroma', name)

        arithmetic = Path(directory) / 'arithmetic.sv'
        arithmetic.write_text('module arithmetic;\n' +
            chroma_function((ROOT / replacements['src/video/coco_cvbs_ntsc.v']).read_text(), 'candidate') + '\n' +
            chroma_function((ROOT / 'src/video/coco_cvbs_ntsc.v').read_text(), 'original') + '''
integer value, phase, operand;
reg signed [10:0] x, y, sum, difference;
initial begin
    for (operand=0; operand<4; operand=operand+1)
        for (value=-1024; value<1024; value=value+1) begin
            x=0; y=0; sum=0; difference=0;
            case (operand)
                0: x=value;
                1: y=value;
                2: sum=value;
                3: difference=value;
            endcase
            for (phase=0; phase<8; phase=phase+1)
                if (candidate(x,y,sum,difference,phase) !== original(x,y,sum,difference,phase))
                    $fatal(1, "YPbPr chroma arithmetic mismatch");
        end
    $display("YPbPr chroma arithmetic PASS: 65536 signed operand/phase cases");
    $finish;
end
endmodule
''')
        binary = str(Path(directory) / 'arithmetic')
        subprocess.run(['iverilog', '-g2012', '-s', 'arithmetic', '-o', binary, str(arithmetic)], check=True)
        subprocess.run(['vvp', binary], check=True)
        for filters in (1, 0):
            binary = str(Path(directory) / f'waveform-{filters}')
            subprocess.run(['iverilog', '-g2012', '-s', 'tb_ypbpr_isolated',
                            f'-Ptb_ypbpr_isolated.REFERENCE_FILTERS={filters}', '-o', binary,
                            'tests/tb_ypbpr_isolated.sv', replacements['src/video/coco_cvbs_ntsc.v'], str(reference)], cwd=ROOT, check=True)
            subprocess.run(['vvp', binary], cwd=ROOT, check=True)
        binary = str(Path(directory) / 'dac-equivalence')
        subprocess.run(['iverilog', '-g2012', '-s', 'tb_ypbpr_dac_equivalence', '-o', binary,
                        'tests/tb_ypbpr_dac_equivalence.sv', replacements['src/video/coco_cvbs_ntsc.v'], str(reference)], cwd=ROOT, check=True)
        subprocess.run(['vvp', binary], cwd=ROOT, check=True)
        binary = str(Path(directory) / 'component-phase')
        subprocess.run(['iverilog', '-g2012', '-s', 'tb_component_dac_phase', '-o', binary,
                        'tests/tb_component_dac_phase.sv', replacements['src/video/coco_cvbs_ntsc.v']], cwd=ROOT, check=True)
        subprocess.run(['vvp', binary], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
