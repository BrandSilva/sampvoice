#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/build/deps/core/sampvoice-3.1.so"
OUT="$ROOT/build/out"

[ -f "$CORE" ] || { echo "missing $CORE, run scripts/fetch-deps.sh first" >&2; exit 1; }
mkdir -p "$OUT"

gcc -std=gnu99 -O0 -g -Wall -Wextra -Wno-unused-result -Wno-unused-function \
    -DSVPORT_CORE_PATH="\"$CORE\"" \
    -o "$OUT/test_config" "$ROOT/plugin/test_config.c" -ldl
"$OUT/test_config"
