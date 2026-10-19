#!/usr/bin/env python3
"""Grab one frame from a C64 Ultimate's VIC video stream and save it as PNG.
Usage: u64grab.py <ultimate-ip> out.png [local-ip] [port]"""
import socket, sys, urllib.request, os
sys.path.insert(0, os.path.dirname(__file__))
from png2x import write_png

PAL = [(0,0,0),(255,255,255),(129,51,56),(117,206,200),(142,60,151),(86,172,77),(46,44,155),
       (237,241,113),(142,80,41),(85,56,0),(196,108,113),(74,74,74),(123,123,123),(169,255,159),
       (112,109,235),(178,178,178)]
ip, out = sys.argv[1], sys.argv[2]
port = int(sys.argv[4]) if len(sys.argv) > 4 else 11000
if len(sys.argv) > 3:
    local = sys.argv[3]
else:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect((ip, 80)); local = s.getsockname()[0]; s.close()

def api(cmd):
    req = urllib.request.Request(f'http://{ip}/v1/streams/video:{cmd}', method='PUT')
    return urllib.request.urlopen(req, timeout=5).read()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('', port)); sock.settimeout(3)
api(f'start?ip={local}:{port}')
lines, started = {}, False
try:
    while True:
        d, _ = sock.recvfrom(2048)
        line = d[4] | d[5] << 8
        last = line & 0x8000
        if not started:
            started = bool(last)
            continue
        lines[line & 0x7FFF] = d[12:]
        if last:
            break
finally:
    api('stop')
rows = []
for y0 in range(0, max(lines) + 4, 4):
    data = lines.get(y0, bytes(768))
    for l in range(4):
        row = b''
        for b in data[l * 192:(l + 1) * 192]:
            row += bytes(PAL[b & 15]) + bytes(PAL[b >> 4])
        rows.append(row)
write_png(out, 384, len(rows), rows)
print(f'{len(rows)} lines from {ip} -> {out}')
