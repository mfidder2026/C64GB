#!/usr/bin/env python3
"""Print the C64 text screen ($0400, lower case charset) of a C64 Ultimate.
Usage: u64screen.py <ultimate-ip> [address-hex]"""
import sys, urllib.request
ip = sys.argv[1]
addr = sys.argv[2] if len(sys.argv) > 2 else '0400'
data = urllib.request.urlopen(f'http://{ip}/v1/machine:readmem?address={addr}&length=1000', timeout=5).read()
def ch(c):
    c &= 0x7F
    if c == 0: return '@'
    if 1 <= c <= 26: return chr(c + 96)
    if 27 <= c <= 31: return '[£]^<'[c - 27]
    if 32 <= c <= 63: return chr(c)
    if 65 <= c <= 90: return chr(c)
    return '.'
for r in range(25):
    print(''.join(ch(c) for c in data[r * 40:(r + 1) * 40]).rstrip())
