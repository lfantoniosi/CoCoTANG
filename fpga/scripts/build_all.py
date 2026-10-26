#!/usr/bin/env python3
"""Build each production FPGA variant and the standalone bus tester sequentially and summarize timing."""
import argparse
import fcntl
import json
import os
import shlex
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = (
    ('default', 'build', 'rebuild', 'CoCoTANG'),
    ('rgb', 'build-rgb', 'rebuild-rgb', 'CoCoTANG-rgb'),
    ('ypbpr', 'build-ypbpr', 'rebuild-ypbpr', 'CoCoTANG-ypbpr'),
    ('cvbs', 'build-cvbs', 'rebuild-cvbs', 'CoCoTANG-cvbs-minimal'),
    ('pal', 'pal-build', 'pal-rebuild', 'CoCoTANG-pal'),
    ('data-test', 'data-test-build', 'data-test-rebuild', 'CoCoTANG-data-test'),
)


def _run_all(mode, make):
    directory = ROOT / 'impl' / f'{mode}-all'
    directory.mkdir(parents=True, exist_ok=True)
    summary = directory / 'summary.json'
    results = []
    for name, build, rebuild, base in VARIANTS:
        target = rebuild if mode == 'rebuild' else build
        log = directory / f'{name}.log'
        output = ROOT / 'impl' / 'pnr' / f'{base}.fs'
        report = ROOT / 'impl' / 'pnr' / f'{base}_tr_content.html'
        print(f'[{len(results)+1}/{len(VARIANTS)}] {target}', flush=True)
        # Gowin shares impl/pnr/device.cfg and cmd.do across all projects.
        # Wait for each make process and force one job even under make -j.
        with log.open('w') as stream:
            completed = subprocess.run([make, '--no-print-directory', '-j1', target],
                                       cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        built = completed.returncode == 0 and output.is_file()
        timing_code = None
        if built and report.is_file():
            timing = subprocess.run([sys.executable, str(ROOT / 'scripts/check_timing.py'), str(report)],
                                    cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            timing_code = timing.returncode
            with log.open('a') as stream:
                stream.write('\n' + timing.stdout)
        timing_status = {0: 'PASS', 1: 'FAIL'}.get(timing_code, 'UNAVAILABLE')
        result = {'variant': name, 'target': target, 'build_exit_code': completed.returncode,
                  'build': 'PASS' if built else 'FAIL', 'timing': timing_status,
                  'output': str(output.relative_to(ROOT)), 'log': str(log.relative_to(ROOT))}
        results.append(result)
        summary.write_text(json.dumps(results, indent=2) + '\n')
        print(f"  build={result['build']} timing={timing_status}; {result['log']}", flush=True)
    print('\nVariant       Build  Timing', flush=True)
    for result in results:
        print(f"{result['variant']:<13} {result['build']:<6} {result['timing']}", flush=True)
    print(f'Summary: {summary.relative_to(ROOT)}', flush=True)
    return 0 if all(item['build'] == 'PASS' and item['timing'] == 'PASS' for item in results) else 1


def run_all(mode, make='make'):
    flags = shlex.split(os.environ.get('MAKEFLAGS', ''))
    short_flags = flags[0] if flags and not flags[0].startswith('-') and '=' not in flags[0] else ''
    dry_run = 'n' in short_flags or any(flag in ('-n', '--dry-run', '--just-print', '--recon') for flag in flags)
    if dry_run:
        for _, build, rebuild, _ in VARIANTS:
            target = rebuild if mode == 'rebuild' else build
            print(shlex.join([make, '--no-print-directory', '-j1', target]))
        return 0
    (ROOT / 'impl').mkdir(exist_ok=True)
    # Also serialize separate aggregate invocations in this workspace.
    with (ROOT / 'impl' / '.all-builds.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _run_all(mode, make)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('build', 'rebuild'))
    parser.add_argument('--make', default='make')
    args = parser.parse_args()
    return run_all(args.mode, args.make)


if __name__ == '__main__':
    sys.exit(main())
