#!/usr/bin/env python3
"""Render the C64 screen of a sim65 frame dump (frame.bin) to PNG.
Usage: framedump.py frame.bin out.png [cgb]   (cgb: $D021 from the dump, else white)"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from png2x import write_png
PAL = [(0,0,0),(255,255,255),(129,51,56),(117,206,200),(142,60,151),(86,172,77),(46,44,155),
       (237,241,113),(142,80,41),(85,56,0),(196,108,113),(74,74,74),(123,123,123),(169,255,159),
       (112,109,235),(178,178,178)]
d = open(sys.argv[1], 'rb').read()
bmp, scr, col = d[:7936] + bytes(64), d[7936:8936], d[8960:9960]
bg = d[9984] & 15 if len(sys.argv) > 3 else 1
rows = []
for y in range(200):
    row = b''
    for x in range(160):
        cell = (y // 8) * 40 + x // 4
        b = bmp[(y // 8) * 320 + (x // 4) * 8 + (y & 7)]
        v = (b >> (6 - 2 * (x & 3))) & 3
        c = [bg, scr[cell] >> 4, scr[cell] & 15, col[cell] & 15][v]
        row += bytes(PAL[c]) * 2
    rows.append(row)
write_png(sys.argv[2], 320, 200, rows)
