"""Keep the hardware-confirmed CVBS sources out of RGB projects."""
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def files(project):
    return [node.attrib['path'] for node in
            ET.parse(ROOT / project).getroot().findall('./FileList/File')]


def main():
    replacements = {'src/top_coco3.v': 'src/cvbs/minimal_top_coco3.v',
                    'src/video/coco_cvbs_ntsc.v': 'src/cvbs/video/coco_cvbs_ntsc_lut.v'}
    normal = files('CoCoTANG-pal.gprj')
    cvbs = files('CoCoTANG-cvbs-minimal.gprj')
    assert cvbs == [replacements.get(name, name) for name in normal]
    for project in ('CoCoTANG.gprj', 'CoCoTANG-pal.gprj'):
        assert not any(name.startswith('src/cvbs/') for name in files(project))
    for name in cvbs:
        assert (ROOT / name).is_file(), name
    for target, project in (('rebuild-rgb', 'CoCoTANG-pal.gprj'),
                            ('rebuild-cvbs', 'CoCoTANG-cvbs-minimal.gprj'),
                            ('ntsc-svideo-rebuild', 'CoCoTANG-cvbs-minimal.gprj')):
        command = subprocess.check_output(['make', '-n', target], cwd=ROOT, text=True)
        assert f'COCOTANG_PROJECT="{project}"' in command, target
        if target != 'rebuild-rgb':
            assert 'COCOTANG_OUTPUT="CoCoTANG-cvbs-minimal"' in command, target
    for target in ('reprogram-cvbs', 'ntsc-svideo-reprogram'):
        command = subprocess.check_output(['make', '-n', target], cwd=ROOT, text=True)
        assert '/impl/pnr/CoCoTANG-cvbs-minimal.fs' in command, target
    print('CVBS isolation PASS: two substitutions; RGB original; CVBS/S-Video use confirmed build identity')


if __name__ == '__main__':
    main()
