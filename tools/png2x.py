#!/usr/bin/env python3
"""Scale a PNG by an integer factor (nearest neighbour) without dependencies.
Usage: png2x.py in.png out.png [factor]"""
import struct, sys, zlib

def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat, plte = 8, b'', None
    while pos < len(data):
        n, typ = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if typ == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
        elif typ == b'PLTE':
            plte = body
        elif typ == b'IDAT':
            idat += body
        pos += 12 + n
    assert interlace == 0 and ctype in (0, 2, 3, 6) and (depth == 8 or ctype in (0, 3))
    bpp = {0: 1, 2: 3, 3: 1, 6: 4}[ctype]
    stride = w * bpp if depth == 8 else (w * depth + 7) // 8
    raw, rows, prev = zlib.decompress(idat), [], bytearray(stride)
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    if depth < 8:                         # unpack sub-byte samples
        per, mask = 8 // depth, (1 << depth) - 1
        rows = [bytearray((r[x // per] >> (8 - depth * (x % per + 1))) & mask for x in range(w)) for r in rows]
        if ctype == 0:
            rows = [bytearray(v * 255 // mask for v in r) for r in rows]
    out = []
    for line in rows:
        if ctype == 0:
            out.append(b''.join(bytes((v, v, v)) for v in line))
        elif ctype == 3:
            out.append(b''.join(plte[i * 3:i * 3 + 3] for i in line))
        elif ctype == 6:
            out.append(b''.join(bytes(line[i:i + 3]) for i in range(0, stride, 4)))
        else:
            out.append(bytes(line))
    return w, h, out

def write_png(path, w, h, rows):
    def chunk(t, b):
        return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    raw = b''.join(b'\x00' + r for r in rows)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

if __name__ == '__main__':
    k = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    w, h, rows = read_png(sys.argv[1])
    big = []
    for r in rows:
        line = b''.join(r[i:i + 3] * k for i in range(0, len(r), 3))
        big += [line] * k
    write_png(sys.argv[2], w * k, h * k, big)
