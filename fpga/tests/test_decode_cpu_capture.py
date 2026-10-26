"""Check real .sr framing, sample selection, channel order and comparison."""
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location('decode_cpu_capture', Path(__file__).resolve().parents[1] / 'scripts/decode_cpu_capture.py')
decoder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = decoder
SPEC.loader.exec_module(decoder)


class DecodeCaptureTest(unittest.TestCase):
    def fixture(self, path, second=0x1B, reverse=False):
        labels = [*(f'D{i}' for i in range(8)), 'reset', 'q', 'e', 'rw', 'a0', 'a1', 'a2', 'a3']
        if reverse:
            labels.reverse()
        values = []
        for tick in range(96):
            read = tick < 50
            data = 0xCC
            e = 24 <= tick < 30 or 40 <= tick < 46 or 56 <= tick < 62
            if 24 <= tick < 29:
                data = 0xAA  # earlier, unsettled data must not be selected
            elif tick == 29:
                data = 0x8C
            elif tick == 45:
                data = second
            elif tick == 61:
                data = 0x37
            signals = {f'D{i}': (data >> i) & 1 for i in range(8)}
            signals.update(reset=int(tick >= 20), q=0, e=int(e), rw=int(read))
            address = 0xE if tick < 35 else 0xF if tick < 50 else 0x2
            signals.update({f'a{i}': (address >> i) & 1 for i in range(4)})
            values.append(sum(signals[label] << bit for bit, label in enumerate(labels)))
        metadata = '[global]\nsigrok version=0.6.0\n\n[device 1]\ncapturefile=logic-1\ntotal probes=16\nsamplerate=1 MHz\nunitsize=2\n'
        metadata += ''.join(f'probe{i+1}={label}\n' for i, label in enumerate(labels))
        raw = struct.pack('<96H', *values)
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('metadata', metadata)
            archive.writestr('version', '2')
            # Twelve chunks, inserted out of order to catch lexical sorting.
            for part in range(12, 0, -1):
                archive.writestr(f'logic-1-{part}', raw[(part-1)*16:part*16])

    def test_edge_sampling_and_reset(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.sr'
            self.fixture(path)
            capture = decoder.Capture(path)
            self.assertEqual(capture.reset_release(), 20)
            cycles = capture.cycles()
            self.assertEqual([c.data for c in cycles], [0x8C, 0x1B, 0x37])
            self.assertEqual([c.sample for c in cycles], [30, 46, 62])
            self.assertEqual([c.read for c in cycles], [1, 1, 0])
            self.assertEqual([c.address_low for c in cycles], [0xE, 0xF, 0x2])
            self.assertEqual([c.data for c in capture.cycles(start=35e-6)], [0x1B, 0x37])

    def test_reordered_channels_and_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            left, right = Path(directory) / 'left.sr', Path(directory) / 'right.sr'
            self.fixture(left)
            self.fixture(right, second=0x19, reverse=True)
            a, b = decoder.Capture(left).cycles(), decoder.Capture(right).cycles()
            differences = decoder.differences(a, b)
            self.assertEqual([index for index, _, _ in differences], [1])
            self.assertEqual((differences[0][1].data, differences[0][2].data), (0x1B, 0x19))


if __name__ == '__main__':
    unittest.main()
