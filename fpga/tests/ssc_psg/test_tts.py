#!/usr/bin/env python3
"""Compare the RTL rule interpreter with an independent regex reference."""
import json
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'src/third_party/nrl_tts'
CLASSES = {'#': '[AEIOUY]+', '.': '[BDVGJLMNRWZ]',
           '%': '(?:ER|E|ES|ED|ING|ELY)', '&': '(?:S|C|G|Z|X|J|CH|SH)',
           '@': '(?:T|S|R|D|L|Z|N|J|TH|CH|SH)',
           '^': '[BCDFGHJKLMNPQRSTVWXZ]', '+': '[EIY]', ':': '[BCDFGHJKLMNPQRSTVWXZ]*'}
ALLOPHONES = ('PA1 PA2 PA3 PA4 PA5 OY AY EH KK3 PP JH NN1 IH TT2 RR1 AX '
              'MM TT1 DH1 IY EY DD1 UW1 AO AA YY2 AE HH1 BB1 TH UH UW2 '
              'AW DD2 GG3 VV GG1 SH ZH RR2 FF KK2 KK1 ZZ NG LL WW XR '
              'WH YY1 CH ER1 ER2 OW DH2 SS NN2 HH2 OR AR YR GG2 EL BB2').split()


def translate(text):
    rules = json.loads((DATA / 'eng_to_ipa.json').read_text())
    mapping = json.loads((DATA / 'ipa_to_sp0256.json').read_text())
    phones = {k: v[0].split('=')[1].strip('[]').split() for k, v in mapping.items() if k != 'PUNCT'}
    phones.update({'< >': ['PA3'], '<,>': ['PA4'], '<.>': ['PA5'], '<?>': ['PA5'], '<->': ['PA4']})
    compiled = []
    for group in rules.values():
        for rule in group:
            pre, body, post, out = re.fullmatch(r'(.*?)\[(.*?)\](.*?)=(.*)', rule).groups()
            regex = lambda part: ''.join(CLASSES.get(c, re.escape(c)) for c in part)
            compiled.append((re.compile(regex(pre) + '$'), body,
                             re.compile('^' + re.escape(body) + regex(post)), out))
    normalized = ' ' + text.upper() + ' '
    normalized = re.sub(r'([^A-Z ]+)', r' \1 ', normalized)
    normalized = re.sub(r'\s+', ' ', normalized)[:511]
    result = []
    pos = 1
    while pos < len(normalized):
        for pre, body, post, out in compiled:
            if pre.search(normalized[:pos]) and post.search(normalized[pos:] + (' ' if len(normalized)==511 else '')):
                for fragment in re.findall(r'/([^/]*)/', out):
                    if fragment.strip():
                        for phone in ([fragment] if fragment.startswith('<') else fragment.split()):
                            result.extend(ALLOPHONES.index(x) for x in phones[phone])
                pos += len(body)
                break
        else:
            pos += 1
    return result + [4]


def main():
    phrases = [
        '', ' ', 'Hello world.', 'I CAN TALK ', 'Color Computer',
        'This is a test of the speech sound cartridge.',
        'The quick brown fox jumps over the lazy dog.',
        "What's your name?", "It's John's computer, isn't it?", '0123456789',
        'Hello there, I am a TI 960A computer.', 'A.I. 1984 - 2026!',
        'Again any ally always also already array air are area arrive',
        'baked hated sealed created riding singer likely being',
        'computer coming comply completion compress',
        'chew new dew few grew drew threw shrew through',
        'unit use union university unique cure pure lure sure',
        'pushed houses boxes horses rises voices edges ages wishes',
        'higher high sigh sign signed design align alignment',
        'colonel rhythm queue choir yacht night enough though thought',
        'one two three four five six seven eight nine zero',
        'ear earth hear heart learn near wear bear pear fear',
        'turn burn fur hurry church during further',
        'WHY who where when which what whose white wharf',
        'yellow year young yes joy eye sky toy boy day',
        'book foot good food mood moon look blood flood',
        'goes shoes does loaves loves moves wolves lives',
        'AEIOUY BCDFGHJKLMNPQRSTVWXZ',
        'abc_123/xyz@foo.com', 'hello\tworld',
        'A' * 200, 'word ' * 100, '123?' * 128,
    ]
    # Exercise every rule's literal in isolation and surrounded by real words.
    source = json.loads((DATA / 'eng_to_ipa.json').read_text())
    phrases.extend(sorted({re.search(r'\[(.*?)\]', r)[1].strip()
                           for group in source.values() for r in group}))
    with tempfile.TemporaryDirectory(prefix='ssc-tts-') as temp:
        temp = Path(temp)
        in_bytes, out_bytes = [], []
        for phrase in phrases:
            data = phrase.encode('ascii')
            output = translate(phrase)
            in_bytes.extend([len(data) >> 8, len(data) & 255, *data])
            out_bytes.extend([len(output) >> 8, len(output) & 255, *output])
        (temp / 'input.hex').write_text(''.join(f'{x:02x}\n' for x in in_bytes))
        (temp / 'expected.hex').write_text(''.join(f'{x:02x}\n' for x in out_bytes))
        subprocess.run(['iverilog', '-g2012', '-s', 'tb_coco_ssc_tts', '-o', str(temp / 'sim'),
                        'tests/tb_coco_ssc_tts.sv', 'src/audio/coco_ssc_tts.v',
                        'src/audio/coco_ssc_tts_rom.v'], cwd=ROOT, check=True)
        subprocess.run(['vvp', str(temp / 'sim'), f'+INPUT={temp}/input.hex',
                        f'+EXPECTED={temp}/expected.hex', f'+PHRASES={len(phrases)}',
                        f'+IN_BYTES={len(in_bytes)}', f'+OUT_BYTES={len(out_bytes)}'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
