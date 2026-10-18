#!/bin/bash
# Pads a Game Boy ROM to a 16 MB REU image (ROM at REU address 0).
set -e
cp "$1" "$2"
truncate -s 16777216 "$2" 2>/dev/null || dd if=/dev/zero of="$2" bs=1 count=0 seek=16777216 2>/dev/null
