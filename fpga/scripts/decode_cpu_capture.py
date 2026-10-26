#!/usr/bin/env python3
"""Decode CPU transactions from packed sigrok .sr captures at E falling.

Expected channel labels: D0..D7, e, rw; optionally reset and a0..a3.
The last sample with E high is used, avoiding post-edge bus release.
"""

import argparse
import configparser
import csv
from dataclasses import dataclass
from pathlib import Path
import re
import zipfile


@dataclass(frozen=True)
class Cycle:
    sample: int
    time_s: float
    read: int
    data: int
    address_low: int | None


class Capture:
    def __init__(self, path):
        self.path = Path(path)
        with zipfile.ZipFile(self.path) as archive:
            metadata = configparser.ConfigParser()
            metadata.read_string(archive.read('metadata').decode())
            device = metadata['device 1']
            rate = re.fullmatch(r'([\d.]+)\s*(Hz|kHz|MHz|GHz)', device['samplerate'])
            if rate is None:
                raise ValueError(f"unsupported sample rate: {device['samplerate']}")
            self.rate = float(rate[1]) * {'Hz': 1, 'kHz': 1e3, 'MHz': 1e6, 'GHz': 1e9}[rate[2]]
            self.width = int(device['unitsize'])
            self.channels = {device[f'probe{i + 1}'].lower(): i
                             for i in range(int(device['total probes']))
                             if f'probe{i + 1}' in device}
            chunks = sorted((name for name in archive.namelist()
                             if re.fullmatch(r'logic-1-\d+', name)),
                            key=lambda name: int(name.rsplit('-', 1)[1]))
            if not chunks:
                raise ValueError('no packed logic-1 capture chunks')
            self.raw = b''.join(archive.read(name) for name in chunks)
        if self.width < 1 or len(self.raw) % self.width:
            raise ValueError('invalid packed sample width or length')
        self.samples = len(self.raw) // self.width
        for label in ('e', 'rw', *(f'd{i}' for i in range(8))):
            if label not in self.channels:
                raise ValueError(f'missing channel {label}')
        self.e = self.flags('e')

    def flags(self, label):
        bit = self.channels[label]
        values = self.raw[bit // 8::self.width]
        return values.translate(bytes((value >> (bit % 8)) & 1 for value in range(256)))

    def bit(self, sample, label):
        bit = self.channels[label]
        return (self.raw[sample * self.width + bit // 8] >> (bit % 8)) & 1

    def reset_release(self, active='low', minimum_us=2):
        """Find release after a sustained reset, ignoring one-sample glitches."""
        if active == 'ignore' or 'reset' not in self.channels:
            return 0
        reset = self.flags('reset')
        asserted = 0 if active == 'low' else 1
        assertion = bytes((1 - asserted, asserted))
        release = bytes((asserted, 1 - asserted))
        start = 0 if reset and reset[0] == asserted else reset.find(assertion) + 1
        if start == 0 and (not reset or reset[0] != asserted):
            return 0
        minimum = max(1, int(self.rate * minimum_us * 1e-6))
        while start < len(reset):
            edge = reset.find(release, start)
            if edge < 0:
                return 0
            if edge + 1 - start >= minimum:
                return edge + 1
            next_edge = reset.find(assertion, edge + 1)
            if next_edge < 0:
                return 0
            start = next_edge + 1
        return 0

    def cycles(self, count=256, start=None, reset_active='low'):
        cursor = int(start * self.rate) if start is not None else self.reset_release(reset_active)
        have_address = all(f'a{i}' in self.channels for i in range(4))
        output = []
        for _ in range(count):
            high = self.e.find(b'\x01\x00', cursor)
            if high < 0:
                break
            falling = high + 1
            data = sum(self.bit(high, f'd{i}') << i for i in range(8))
            address = sum(self.bit(high, f'a{i}') << i for i in range(4)) if have_address else None
            output.append(Cycle(falling, falling / self.rate, self.bit(high, 'rw'), data, address))
            cursor = falling
        return output


def differences(left, right):
    output = []
    for index, (a, b) in enumerate(zip(left, right)):
        compare_address = a.address_low is not None and b.address_low is not None
        if a.read != b.read or a.data != b.data or (compare_address and a.address_low != b.address_low):
            output.append((index, a, b))
    return output


def describe(cycle):
    low = '?' if cycle.address_low is None else f'{cycle.address_low:X}'
    return f"{cycle.time_s:.9f} {'R' if cycle.read else 'W'} A[3:0]={low} D={cycle.data:02X}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--compare', type=Path, help='second capture, independently aligned to reset release')
    parser.add_argument('--start', type=float, help='explicit start time in seconds; overrides reset alignment')
    parser.add_argument('--compare-start', type=float, help='explicit second-capture start time')
    parser.add_argument('--reset-active', choices=('low', 'high', 'ignore'), default='low')
    parser.add_argument('--cycles', type=int, default=256)
    parser.add_argument('--csv', type=Path, help='write decoded transactions as CSV')
    args = parser.parse_args()
    if args.cycles < 1 or any(value is not None and value < 0 for value in (args.start, args.compare_start)):
        parser.error('cycle count must be positive; start times must be nonnegative')
    first = Capture(args.capture)
    cycles = first.cycles(args.cycles, args.start, args.reset_active)
    print(f'{first.path}: {first.rate:g} samples/s, {1e9 / first.rate:.1f} ns/sample, {len(cycles)} cycles')
    for index, cycle in enumerate(cycles[:32]):
        print(f'{index:5d} {describe(cycle)}')
    if args.csv:
        with args.csv.open('w', newline='') as file:
            writer = csv.writer(file)
            writer.writerow(('cycle', 'sample', 'time_s', 'rw', 'data_hex', 'address_low_hex'))
            for index, cycle in enumerate(cycles):
                writer.writerow((index, cycle.sample, f'{cycle.time_s:.9f}', 'R' if cycle.read else 'W',
                                 f'{cycle.data:02X}', '' if cycle.address_low is None else f'{cycle.address_low:X}'))
    if args.compare:
        second = Capture(args.compare)
        other = second.cycles(args.cycles, args.compare_start, args.reset_active)
        changed = differences(cycles, other)
        print(f'{second.path}: {len(other)} cycles; {len(changed)} differing transactions in {min(len(cycles), len(other))} paired cycles')
        for index, a, b in changed[:8]:
            print(f'{index:5d} first:  {describe(a)}\n      second: {describe(b)}')
        if len(cycles) != len(other):
            print('Captures have different decoded lengths.')
        print('Comparisons use cycle order after reset; interrupt or I/O timing can cause legitimate divergence.')


if __name__ == '__main__':
    main()
