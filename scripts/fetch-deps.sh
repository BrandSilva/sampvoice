#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/build/deps"

CORE_ZIP_URL="https://github.com/CyberMor/sampvoice/releases/download/v3.1/sv_server_037.zip"
CORE_ZIP_SHA256="9938431df6a1f19d52e64fd71e616e270e81bdff777c8a8bc2de73c2012ee3ff"
CORE_SHA256="072915b5648b0fc9987eafdb6a10d6cd86786bb44f7121cf4e6dc56046aa7382"

PAWNC_URL="https://github.com/pawn-lang/compiler/releases/download/v3.10.10/pawnc-3.10.10-linux.tar.gz"
PAWNC_SHA256="9bbb1df6e933318fce1fa61951e4196b70613c637a5a1d4c96937e147c18468d"

SAMP_WIN_URL="https://raw.githubusercontent.com/KrustyKoyle/files.sa-mp.com-Archive/master/samp037_svr_R2-1-1_win32.zip"
SAMP_WIN_SHA256="e12e7483d4df0349f52e2c5f47d6afd3f782acbc2bbb19fa61adced3bfff2d90"

fetch() {
    local url="$1" sha="$2" dest="$3"
    if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c --status -; then
        return
    fi
    echo "fetching $url"
    curl -fsSL --retry 3 --connect-timeout 20 -o "$dest.part" "$url"
    if ! echo "$sha  $dest.part" | sha256sum -c --status -; then
        echo "checksum mismatch for $url" >&2
        echo "expected $sha, got $(sha256sum "$dest.part" | cut -d' ' -f1)" >&2
        rm -f "$dest.part"
        exit 1
    fi
    mv "$dest.part" "$dest"
}

mkdir -p "$DEPS/core" "$DEPS/pawnc" "$DEPS/samp-include"

fetch "$CORE_ZIP_URL" "$CORE_ZIP_SHA256" "$DEPS/sv_server_037.zip"
unzip -o -q -j "$DEPS/sv_server_037.zip" sampvoice.so -d "$DEPS/core"
mv -f "$DEPS/core/sampvoice.so" "$DEPS/core/sampvoice-3.1.so"
echo "$CORE_SHA256  $DEPS/core/sampvoice-3.1.so" | sha256sum -c

fetch "$PAWNC_URL" "$PAWNC_SHA256" "$DEPS/pawnc.tar.gz"
tar -xzf "$DEPS/pawnc.tar.gz" -C "$DEPS/pawnc" --strip-components=1

fetch "$SAMP_WIN_URL" "$SAMP_WIN_SHA256" "$DEPS/samp_win32.zip"
unzip -o -q -j "$DEPS/samp_win32.zip" 'pawno/include/*' -d "$DEPS/samp-include"

echo "dependencies ready in $DEPS"
