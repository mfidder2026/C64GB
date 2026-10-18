#!/bin/bash
# Runs a ROM in VICE (warp, REU) for N C64 cycles and saves a screenshot.
# Usage: tools/shot.sh rom.gb cycles out.png ["frame:buttons:dirs ..."]
#   buttons: 1=A 2=B 4=Select 8=Start   dirs: 1=Right 2=Left 4=Up 8=Down
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PRG="$ROOT/build/c64gb.prg"
if [ -n "$4" ]; then
    for k in $4; do IFS=: read f b d <<<"$k"; echo "        .word $f"; echo "        .byte $b, ${d:-0}"; done > "$TMP/autokeys.inc"
    "$ROOT/tools/cc65-src/bin/ca65" -I "$ROOT/src" -I "$TMP" -D TARGET_C64=1 -D AUTOKEYS=1 \
        -o "$TMP/c64.o" "$ROOT/src/main_c64.s"
    "$ROOT/tools/cc65-src/bin/ld65" -C "$ROOT/cfg/c64.cfg" -o "$TMP/c64gb.prg" "$TMP/c64.o"
    PRG="$TMP/c64gb.prg"
fi
"$ROOT/tools/mkreu.sh" "$1" "$TMP/rom.reu"
"$ROOT/tools/vice/bin/x64sc" -default -autostartprgmode 1 -reu -reusize 16384 \
    -reuimage "$TMP/rom.reu" +reuimagerw -warp -limitcycles "$2" -exitscreenshot "$3" \
    -autostart "$PRG" >/dev/null 2>&1 || true
