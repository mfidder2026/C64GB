#!/bin/bash
# Fetches and builds everything C64GB needs, inside the project folder:
#   tools/cc65-src  cc65 (ca65, ld65, sim65) built from source
#   tools/vice      VICE 3.10 (macOS arm64 build) for visual testing
#   tests/          Blargg's test ROMs, dmg-acid2 and cgb-acid2
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x tools/cc65-src/bin/ca65 ]; then
    git clone --depth 1 https://github.com/cc65/cc65.git tools/cc65-src
    make -C tools/cc65-src -j8 bin
fi

if [ ! -x tools/vice/bin/x64sc ] && [ "$(uname)" = Darwin ]; then
    dmg="$(mktemp -t vice).dmg"; mnt="$(mktemp -d)"
    curl -L -o "$dmg" "https://sourceforge.net/projects/vice-emu/files/releases/binaries/macosx/vice-arm64-gtk3-3.10.dmg/download"
    hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null
    cp -R "$mnt/vice-arm64-gtk3-3.10" tools/vice
    hdiutil detach "$mnt" >/dev/null; rm -f "$dmg"
    xattr -dr com.apple.quarantine tools/vice 2>/dev/null || true
fi

[ -d tests/gb-test-roms ] || git clone --depth 1 https://github.com/retrio/gb-test-roms.git tests/gb-test-roms
mkdir -p tests/roms
[ -f tests/roms/dmg-acid2.gb ] || curl -L -o tests/roms/dmg-acid2.gb \
    https://github.com/mattcurrie/dmg-acid2/releases/download/v1.0/dmg-acid2.gb
[ -f tests/roms/cgb-acid2.gbc ] || curl -L -o tests/roms/cgb-acid2.gbc \
    https://github.com/mattcurrie/cgb-acid2/releases/download/v1.1/cgb-acid2.gbc
echo "setup complete"
