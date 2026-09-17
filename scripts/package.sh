#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/^#define SVPORT_VERSION "\(.*\)"$/\1/p' plugin/svport.c)"
[ -n "$VERSION" ] || { echo "cannot read SVPORT_VERSION from plugin/svport.c" >&2; exit 1; }

if [ -n "${GITHUB_REF_NAME:-}" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ "$GITHUB_REF_NAME" != "v$VERSION" ]; then
    echo "tag $GITHUB_REF_NAME does not match SVPORT_VERSION $VERSION" >&2
    exit 1
fi

STAGE=build/stage
rm -rf "$STAGE" dist
mkdir -p "$STAGE/plugins" "$STAGE/filterscripts" "$STAGE/pawno/include" "$STAGE/sampvoice-port" dist

cp build/out/sampvoice.so "$STAGE/plugins/sampvoice.so"
cp build/out/voice.amx "$STAGE/filterscripts/voice.amx"
cp filterscripts/voice.pwn "$STAGE/filterscripts/voice.pwn"
cp include/sampvoice.inc "$STAGE/pawno/include/sampvoice.inc"
cp package/LEEME.md package/server.cfg.example LICENSE LICENSE-sampvoice "$STAGE/sampvoice-port/"
echo "$VERSION" > "$STAGE/sampvoice-port/VERSION"

(cd "$STAGE" && find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > sampvoice-port/SHA256SUMS)
(cd "$STAGE" && zip -qr -X "$ROOT/dist/sampvoice-port.zip" .)
(cd dist && sha256sum sampvoice-port.zip > SHA256SUMS)

PLUGIN_SHA="$(sha256sum build/out/sampvoice.so | cut -d' ' -f1)"
ZIP_SHA="$(sha256sum dist/sampvoice-port.zip | cut -d' ' -f1)"

cat > dist/RELEASE_NOTES.md <<NOTES
SampVoice 3.1 con puerto de voz fijo, para SA-MP 0.3.7-R2-1 en Linux.

- \`sv_port\` en \`server.cfg\` (o la variable \`SV_PORT\`) fija el puerto UDP de la voz.
- Convive con Pawn.RakNet: evita el fallo de la 3.1 que tumba el servidor al arrancar.
- Los jugadores usan el cliente oficial de SampVoice 3.1 (SA-MP 0.3.7-R1 o R3), sin cambios.

Instalación y opciones: \`sampvoice-port/LEEME.md\` dentro del zip.

\`\`\`
sampvoice-port.zip  $ZIP_SHA
plugins/sampvoice.so  $PLUGIN_SHA
\`\`\`
NOTES

echo "version $VERSION"
ls -l dist
cat dist/SHA256SUMS
