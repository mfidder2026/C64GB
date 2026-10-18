#!/bin/bash
# Runs Blargg's Game Boy test ROMs in sim65 and reports pass/fail.
# Usage: tests/run_blargg.sh [rom.gb ...]   (default: cpu_instrs individual tests)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM65="$ROOT/tools/cc65-src/bin/sim65"
BIN="$ROOT/build/c64gb-sim.bin"
LIMIT=${LIMIT:-4000000000}
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ $# -eq 0 ]; then
    set -- "$ROOT"/tests/gb-test-roms/cpu_instrs/individual/*.gb
fi

pass=0; fail=0
for rom in "$@"; do
    cp "$rom" "$WORK/rom.gb"
    out="$(cd "$WORK" && "$SIM65" -c -x "$LIMIT" "$BIN" 2>&1)"
    name="$(basename "$rom")"
    if echo "$out" | grep -q "Passed"; then
        pass=$((pass+1)); printf "PASS  %-28s %s\n" "$name" "$(echo "$out" | grep -o '\[cycles.*\]\|[0-9]* cycles' | tr '\n' ' ')"
    else
        fail=$((fail+1)); printf "FAIL  %-28s\n" "$name"; echo "$out" | tail -5 | sed 's/^/      /'
    fi
done
echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
