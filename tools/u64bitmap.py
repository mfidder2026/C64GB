#!/usr/bin/env python3
"""Read the C64GB bitmap from a C64 Ultimate (REST readmem) and save a PNG.
Screen RAM sits under I/O and cannot be read, so the DMG colours are assumed.
Usage: u64bitmap.py <ultimate-ip> out.png"""
import sys, os, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from png2x import write_png
PAL = [(0,0,0),(255,255,255),(129,51,56),(117,206,200),(142,60,151),(86,172,77),(46,44,155),
       (237,241,113),(142,80,41),(85,56,0),(196,108,113),(74,74,74),(123,123,123),(169,255,159),
       (112,109,235),(178,178,178)]
ip = sys.argv[1]
rd = lambda a, n: urllib.request.urlopen(f'http://{ip}/v1/machine:readmem?address={a}&length={n}', timeout=10).read()
bmp = rd('E000', 8000)
col = rd('D800', 1000)
rows = []
for y in range(200):
    row = b''
    for x in range(160):
        cell = (y // 8) * 40 + x // 4
        b = bmp[(y // 8) * 320 + (x // 4) * 8 + (y & 7)]
        v = (b >> (6 - 2 * (x & 3))) & 3
        c = [1, 15, 11, col[cell] & 15][v]
        row += bytes(PAL[c]) * 2
    rows.append(row)
write_png(sys.argv[2], 320, 200, rows)
print('saved', sys.argv[2])
