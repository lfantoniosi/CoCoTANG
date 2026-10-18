#!/usr/bin/env python3
"""Encode the XRoar GIME glyph reference into the compatibility font bank.

The existing character address and polarity mapping is retained. Bank zero
(native text) and unreachable compatibility slots are preserved byte-for-byte.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = ROOT / 'tests/data/gime_font_xroar.hex'
OUTPUT = ROOT / 'src/coco3/coco3_char.hex'


def update():
    font = [int(line, 16) for line in REFERENCE.read_text().splitlines()
            if re.fullmatch(r'[0-9a-fA-F]{2}', line)]
    rom = [int(value, 16) for value in OUTPUT.read_text().split()]
    assert len(font) == 128 * 12 and len(rom) == 4096
    entries = {}
    inverse_groups = {0, 1, 5, 10, 11, 12, 14, 15}
    for gm in range(4):
        for character in range(128):
            # XRoar's GIME compatibility character selection and inversion.
            glyph = character
            inverse = bool(character & 64) ^ bool(gm & 2)
            if glyph < 32:
                glyph |= 96 if gm & 1 else 64
                inverse ^= bool(gm & 1)
            elif glyph >= 96:
                glyph ^= 64
            # Preserve the FPGA ROM address and decode-polarity convention.
            slot = ((96 | (character & 31)) if gm & 1 and character & 96 == 0
                    else (((~character >> 5) & 1) << 6) | (character & 63))
            old_inverse = (gm * 4 + (character >> 5)) in inverse_groups
            for row in range(16):
                data = font[glyph * 12 + row] if row < 12 else 0
                data ^= 255 if inverse else 0
                encoded = (data ^ 255) ^ (255 if old_inverse else 0)
                address = 2048 + slot * 16 + row
                if address in entries:
                    assert entries[address] == encoded, 'conflicting ROM alias'
                entries[address] = encoded
    for address, value in entries.items():
        rom[address] = value
    OUTPUT.write_text(''.join(f'{value:02x}\n' for value in rom))
    print(f'Updated {len(entries)} compatibility bytes; native bank preserved')


if __name__ == '__main__':
    update()
