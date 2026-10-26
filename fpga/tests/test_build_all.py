"""Exercise aggregate target selection and failures without running Gowin."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location('build_all', Path(__file__).resolve().parents[1] / 'scripts/build_all.py')
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class BuildAllTest(unittest.TestCase):
    def workspace(self, root):
        (root / 'scripts').mkdir()
        (root / 'scripts/check_timing.py').write_text("import pathlib,sys\nsys.exit(1 if pathlib.Path(sys.argv[1]).read_text() == 'fail' else 0)\n")
        make = root / 'fake-make'
        make.write_text('''#!/usr/bin/env python3
import json,pathlib,sys
root=pathlib.Path.cwd()
with (root/'calls.jsonl').open('a') as stream:stream.write(json.dumps(sys.argv[1:])+'\\n')
name=sys.argv[-1].split('-',1)[1]
if name=='compile-fail':sys.exit(2)
pnr=root/'impl/pnr';pnr.mkdir(parents=True,exist_ok=True)
(pnr/(name+'.fs')).write_text('bitstream')
if name!='no-report':(pnr/(name+'_tr_content.html')).write_text('fail' if name=='timing-fail' else 'pass')
''')
        make.chmod(0o755)
        return make

    def test_continues_after_build_and_timing_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make = self.workspace(root)
            variants = tuple((name, 'build-'+name, 'rebuild-'+name, name)
                             for name in ('compile-fail', 'timing-fail', 'no-report', 'last'))
            with patch.object(runner, 'ROOT', root), patch.object(runner, 'VARIANTS', variants), contextlib.redirect_stdout(io.StringIO()):
                status = runner.run_all('build', str(make))
            self.assertEqual(status, 1)
            summary = json.loads((root / 'impl/build-all/summary.json').read_text())
            self.assertEqual([row['build'] for row in summary], ['FAIL', 'PASS', 'PASS', 'PASS'])
            self.assertEqual([row['timing'] for row in summary], ['UNAVAILABLE', 'FAIL', 'UNAVAILABLE', 'PASS'])
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            self.assertEqual([call[-1] for call in calls], [row[1] for row in variants])
            self.assertTrue(all('-j1' in call for call in calls))
            self.assertTrue(all((root / row['log']).is_file() for row in summary))

    def test_make_dry_run_has_no_output_side_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(runner, 'ROOT', root), patch.dict(os.environ, {'MAKEFLAGS': 'n --no-print-directory'}), contextlib.redirect_stdout(io.StringIO()) as output:
                status = runner.run_all('rebuild')
            self.assertEqual(status, 0)
            self.assertIn('rebuild-cvbs', output.getvalue())
            self.assertFalse((root / 'impl').exists())

    def test_rebuild_mode_uses_force_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make = self.workspace(root)
            variants = (('one', 'build-one', 'rebuild-one', 'one'), ('two', 'build-two', 'rebuild-two', 'two'))
            with patch.object(runner, 'ROOT', root), patch.object(runner, 'VARIANTS', variants), contextlib.redirect_stdout(io.StringIO()):
                status = runner.run_all('rebuild', str(make))
            self.assertEqual(status, 0)
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            self.assertEqual([call[-1] for call in calls], ['rebuild-one', 'rebuild-two'])


if __name__ == '__main__':
    unittest.main()
