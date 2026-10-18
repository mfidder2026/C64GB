#!/bin/bash
# Prints C64 cycles per GB M-cycle and the speed this gives at several turbo clocks.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$1" "$WORK/rom.gb"
for v in bench benchr; do
    out="$(cd "$WORK" && "$ROOT/tools/cc65-src/bin/sim65" -c "$ROOT/build/$v.bin" 2>&1)"
    gb=$((16#$(echo "$out" | grep -o 'cycles \$[0-9A-F]*' | tr -d 'cycles $')))
    c64=$(echo "$out" | grep -o '^[0-9]* cycles' | grep -o '[0-9]*')
    label=$([ $v = bench ] && echo "CPU only        " || echo "CPU + rendering ")
    awk -v g=$gb -v c=$c64 -v l="$label" 'BEGIN { r=c/g; printf "%s %6.1f C64 cycles per GB cycle -> 48 MHz: %3.0f%%  64 MHz: %3.0f%% of GB speed\n", l, r, 48e6/r/1048576*100, 64e6/r/1048576*100 }'
done
