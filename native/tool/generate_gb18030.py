"""Regenerate GB18030 mapping data with Python's built-in codec.

Run from any directory: python3 native/tool/generate_gb18030.py
Two-byte characters use a dense table; four-byte sequences use linear ranges.
The resulting asset needs no platform converter or network access at runtime.
"""

import gzip
import json
from pathlib import Path


def four_byte_sequence(pointer):
    fourth = pointer % 10 + 0x30
    pointer //= 10
    third = pointer % 126 + 0x81
    pointer //= 126
    second = pointer % 10 + 0x30
    first = pointer // 10 + 0x81
    return bytes([first, second, third, fourth])


def generate():
    pairs = []
    trailing_bytes = list(range(0x40, 0x7F)) + list(range(0x80, 0xFF))
    for leading in range(0x81, 0xFF):
        for trailing in trailing_bytes:
            pairs.append(ord(bytes([leading, trailing]).decode('gb18030')))

    ranges = []
    previous = -2
    for pointer in range(126 * 10 * 126 * 10):
        try:
            codepoint = ord(four_byte_sequence(pointer).decode('gb18030'))
        except UnicodeDecodeError:
            previous = -2
            continue
        if codepoint != previous + 1:
            ranges.append([pointer, codepoint, pointer])
        else:
            ranges[-1][2] = pointer
        previous = codepoint

    output = Path(__file__).resolve().parents[1] / 'assets/terminal/gb18030.json.gz'
    payload = json.dumps({'pairs': pairs, 'ranges': ranges}, separators=(',', ':'))
    output.write_bytes(gzip.compress(payload.encode(), mtime=0))
    print(f'{output}: {output.stat().st_size} bytes, {len(ranges)} ranges')


if __name__ == '__main__':
    generate()
