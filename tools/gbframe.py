#!/usr/bin/env python3
"""Extract the 160x144 Game Boy frame from a VICE screenshot of C64GB and
optionally compare it with a reference PNG (e.g. dmg-acid2's reference image).
Usage: gbframe.py vice.png out.png [reference.png]"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from png2x import read_png, write_png

X0, Y0 = 32, 35 + 3 * 8          # VICE border + TOP_ROW cell rows

def shade(rgb):                   # map C64 greys / reference greys to 0..3 (0 = white)
    v = sum(rgb) / 3
    return 0 if v > 230 else 1 if v > 150 else 2 if v > 50 else 3

w, h, rows = read_png(sys.argv[1])
frame = [[shade(rows[Y0 + y][(X0 + 2 * x) * 3:(X0 + 2 * x) * 3 + 3]) for x in range(160)] for y in range(144)]
pal = [b'\xff\xff\xff', b'\xaa\xaa\xaa', b'\x55\x55\x55', b'\x00\x00\x00']
write_png(sys.argv[2], 160, 144, [b''.join(pal[s] for s in r) for r in frame])
if len(sys.argv) > 3:
    rw, rh, ref = read_png(sys.argv[3])
    diff = sum(frame[y][x] != shade(ref[y][x * 3:x * 3 + 3]) for y in range(144) for x in range(160))
    print(f"{diff} of {160 * 144} pixels differ from the reference")
