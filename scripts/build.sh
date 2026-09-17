#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${BUILD_IMAGE:-i386/ubuntu:18.04}"
cd "$ROOT"

./scripts/fetch-deps.sh
mkdir -p build/out dist

docker run --rm -v "$ROOT":/src -w /src \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    "$IMAGE" bash -c '
set -euo pipefail
apt-get update -qq >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc libc6-dev binutils file >/dev/null
gcc --version | head -1
plugin/test.sh
plugin/build.sh
scripts/compile-pawn.sh
chown -R "$HOST_UID:$HOST_GID" build
'

./scripts/package.sh
