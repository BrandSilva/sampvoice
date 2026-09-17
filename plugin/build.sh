#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/build/deps/core/sampvoice-3.1.so"
OUT="$ROOT/build/out"

[ -f "$CORE" ] || { echo "missing $CORE, run scripts/fetch-deps.sh first" >&2; exit 1; }
mkdir -p "$OUT"

gcc -std=gnu99 -O2 -fPIC -shared -fvisibility=hidden -Wall -Wextra -Werror \
    -DSVPORT_CORE_PATH="\"$CORE\"" \
    -o "$OUT/sampvoice.so" "$ROOT/plugin/svport.c" \
    -ldl -Wl,-z,noexecstack -Wl,--as-needed
strip -s "$OUT/sampvoice.so"

file "$OUT/sampvoice.so"
sha256sum "$OUT/sampvoice.so"
