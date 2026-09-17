#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/build/deps"
OUT="$ROOT/build/out"

mkdir -p "$OUT"
LD_LIBRARY_PATH="$DEPS/pawnc/lib" "$DEPS/pawnc/bin/pawncc" \
    "$ROOT/filterscripts/voice.pwn" \
    -i"$ROOT/include" -i"$DEPS/samp-include" \
    -o"$OUT/voice.amx" '-;+' '-(+' -O1
[ -f "$OUT/voice.amx" ] || { echo "voice.amx was not produced" >&2; exit 1; }
