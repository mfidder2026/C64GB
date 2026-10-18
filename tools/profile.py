#!/usr/bin/env python3
"""Cycle profile of the emulator running a ROM in sim65.
Usage: tools/profile.py rom.gb [start_frame] [frames] [render]
Builds a tracing sim binary, runs it, and prints C64 cycles per routine."""
import collections, os, re, subprocess, sys, tempfile, bisect

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rom = sys.argv[1]
start = int(sys.argv[2]) if len(sys.argv) > 2 else 60
count = int(sys.argv[3]) if len(sys.argv) > 3 else 2
render = len(sys.argv) > 4 and sys.argv[4] == 'render'
tmp = tempfile.mkdtemp()
bin_ = os.path.join(tmp, 'prof.bin')
defs = ['-D', 'TARGET_SIM=1', '-D', f'PROFILE={start}', '-D', f'PROF_N={count}']
if render:
    defs += ['-D', 'RENDER=1']
tools = os.path.join(ROOT, 'tools/cc65-src/bin')
subprocess.check_call([f'{tools}/ca65', '-g', '-I', f'{ROOT}/src'] + defs +
                      ['-o', f'{tmp}/p.o', f'{ROOT}/src/main_sim.s'])
subprocess.check_call([f'{tools}/ld65', '-C', f'{ROOT}/cfg/sim.cfg', '-o', bin_,
                       '--dbgfile', f'{tmp}/p.dbg', f'{tmp}/p.o'])
syms = []
for line in open(f'{tmp}/p.dbg'):
    if line.startswith('sym') and 'type=lab' in line:
        name = re.search(r'name="([^"]+)"', line).group(1)
        val = re.search(r'val=0x([0-9A-Fa-f]+)', line)
        if val and not name.startswith('@') and '__' not in name:
            syms.append((int(val.group(1), 16), name))
syms.sort()
addrs = [a for a, _ in syms]
os.symlink(os.path.abspath(rom), f'{tmp}/rom.gb')
proc = subprocess.Popen([f'{tools}/sim65', bin_], cwd=tmp, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True)
cyc = collections.Counter()
prev_clock = prev_pc = None
total = 0
for line in proc.stdout:
    m = re.match(r'\s*(\d+)\s+([0-9A-F]{4})\s*$', line)
    if not m:
        continue
    clock, pc = int(m.group(1)), int(m.group(2), 16)
    if prev_pc is not None:
        i = bisect.bisect_right(addrs, prev_pc) - 1
        name = syms[i][1] if i >= 0 else '?'
        cyc[name] += clock - prev_clock
        total += clock - prev_clock
    prev_clock, prev_pc = clock, pc
print(f'{total} C64 cycles traced over {count} frame(s)')
acc = 0
for name, c in cyc.most_common(40):
    acc += c
    print(f'{c:10d} {100*c/total:5.1f}% {100*acc/total:5.1f}%  {name}')
