#!/bin/bash
# SA-MP TridentSky Edition + SampVoice 3.1 con puerto fijo
# Instalacion idempotente: nunca pisa archivos que ya existan en el servidor.
set -euo pipefail

SERVER=/mnt/server
CFG="$SERVER/server.cfg"

SAMP_URL="https://raw.githubusercontent.com/KrustyKoyle/files.sa-mp.com-Archive/master/samp037svr_R2-1.tar.gz"
SAMP_SHA256="f8ead0b15683fc34f13a7a84ba9ea7252b17c5e3161d8255364e1abedd697a53"
MYSQL_URL="https://github.com/pBlueG/SA-MP-MySQL/releases/download/R41-4/mysql-R41-4-Debian-static.tar.gz"
MYSQL_SHA256="2e24aabfb7d674a454961e341a7df219f65069d273c44d4323e5199a59f135be"

echo "[1/5] Dependencias"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates unzip tar file >/dev/null

mkdir -p "$SERVER"
cd /tmp

echo "[2/5] Servidor SA-MP 0.3.7-R2"
if [ ! -f "$SERVER/samp03svr" ]; then
    curl -fsSL --retry 3 --connect-timeout 20 -o samp.tar.gz "$SAMP_URL"
    echo "$SAMP_SHA256  samp.tar.gz" | sha256sum -c -
    rm -rf samp && mkdir -p samp
    tar -xzf samp.tar.gz -C samp --strip-components=1
    install -m 755 samp/samp03svr samp/samp-npc samp/announce "$SERVER/"
    for dir in gamemodes filterscripts npcmodes scriptfiles include; do
        [ -e "$SERVER/$dir" ] || cp -r "samp/$dir" "$SERVER/$dir"
    done
    [ -f "$CFG" ] || cp samp/server.cfg "$CFG"
    echo "  servidor instalado"
else
    echo "  ya existe samp03svr, no se toca"
    [ -f "$CFG" ] || printf 'echo Executing Server Config...\n' > "$CFG"
fi

sed -i 's/\r$//' "$CFG"
chmod 755 "$SERVER/samp03svr" "$SERVER/samp-npc" "$SERVER/announce" 2>/dev/null || true

ensure_key() {
    grep -qiE "^$1([[:space:]]|$)" "$CFG" || printf '%s %s\n' "$1" "$2" >> "$CFG"
}

ensure_key port "${SERVER_PORT:-7777}"
ensure_key maxplayers "${MAX_PLAYERS:-50}"
ensure_key rcon_password "${RCON_PASS:-changeme}"
ensure_key hostname "${SERVER_NAME:-SA-MP Server}"
ensure_key announce 0
ensure_key query 1

echo "[3/5] Plugin MySQL"
if [ "${INSTALL_MYSQL:-0}" = "1" ] || [ "${INSTALL_MYSQL:-0}" = "true" ]; then
    if [ -f "$SERVER/plugins/mysql.so" ]; then
        echo "  ya existe mysql.so, no se toca"
    elif curl -fsSL --retry 3 --connect-timeout 20 -o mysql.tar.gz "$MYSQL_URL" && echo "$MYSQL_SHA256  mysql.tar.gz" | sha256sum -c -; then
        rm -rf mysqlplugin && mkdir -p mysqlplugin
        tar -xzf mysql.tar.gz -C mysqlplugin
        SO="$(find mysqlplugin -name 'mysql_static.so' -o -name 'mysql.so' | head -1)"
        LOGCORE="$(find mysqlplugin -name 'log-core.so' | head -1)"
        if [ -n "$SO" ]; then
            mkdir -p "$SERVER/plugins"
            install -m 644 "$SO" "$SERVER/plugins/mysql.so"
            [ -n "$LOGCORE" ] && install -m 644 "$LOGCORE" "$SERVER/log-core.so"
            echo "  mysql.so instalado"
        else
            echo "  aviso: no se encontro mysql.so en el paquete"
        fi
    else
        echo "  aviso: no se pudo descargar el plugin MySQL"
    fi
else
    echo "  omitido"
fi

echo "[4/5] SampVoice 3.1 con puerto fijo"
if [ "${INSTALL_VOICE:-1}" = "1" ] || [ "${INSTALL_VOICE:-1}" = "true" ]; then
    TAG="${SVPORT_VERSION:-latest}"
    if [ "$TAG" = "latest" ]; then
        VOICE_URL="https://github.com/BrandSilva/sampvoice/releases/latest/download/sampvoice-port.zip"
    else
        VOICE_URL="https://github.com/BrandSilva/sampvoice/releases/download/${TAG}/sampvoice-port.zip"
    fi
    curl -fsSL --retry 3 --connect-timeout 20 -o sampvoice-port.zip "$VOICE_URL"
    rm -rf sv && mkdir -p sv
    unzip -q -o sampvoice-port.zip -d sv
    (cd sv && sha256sum -c sampvoice-port/SHA256SUMS)

    mkdir -p "$SERVER/plugins" "$SERVER/filterscripts" "$SERVER/pawno/include"
    install -m 644 sv/plugins/sampvoice.so "$SERVER/plugins/sampvoice.so"
    install -m 644 sv/pawno/include/sampvoice.inc "$SERVER/pawno/include/sampvoice.inc"
    [ -f "$SERVER/filterscripts/voice.amx" ] || install -m 644 sv/filterscripts/voice.amx "$SERVER/filterscripts/voice.amx"
    [ -f "$SERVER/filterscripts/voice.pwn" ] || install -m 644 sv/filterscripts/voice.pwn "$SERVER/filterscripts/voice.pwn"

    ensure_key sv_port "${SV_PORT:-}"

    if grep -qiE "^plugins([[:space:]]|$)" "$CFG"; then
        if grep -qiE "^plugins.*sampvoice[^.]" "$CFG" && ! grep -qiE "^plugins.*sampvoice\.so" "$CFG"; then
            sed -i -E "s/^(plugins.*)sampvoice([^.]|$)/\1sampvoice.so\2/I" "$CFG"
        elif ! grep -qiE "^plugins.*sampvoice" "$CFG"; then
            sed -i -E "s/^(plugins.*[^[:space:]])[[:space:]]*$/\1 sampvoice.so/I" "$CFG"
        fi
    else
        echo "plugins sampvoice.so" >> "$CFG"
    fi

    if [ "${VOICE_FILTERSCRIPT:-1}" = "1" ] || [ "${VOICE_FILTERSCRIPT:-1}" = "true" ]; then
        if grep -qiE "^filterscripts([[:space:]]|$)" "$CFG"; then
            grep -qiE "^filterscripts.*[[:space:]]voice([[:space:]]|$)" "$CFG" || \
                sed -i -E "s/^filterscripts[[:space:]]*(.*)$/filterscripts voice \1/I" "$CFG"
        else
            echo "filterscripts voice" >> "$CFG"
        fi
    fi
    echo "  modulo de voz instalado (sv_port = ${SV_PORT:-sin asignar})"
else
    echo "  omitido"
fi

echo "[5/5] Arranque controlado y permisos"
cat > "$SERVER/start.sh" <<'STARTSH'
#!/bin/bash
cd /home/container || exit 1

STOP_TIMEOUT="${STOP_TIMEOUT:-30}"

matar_npcs() {
    for dir in /proc/[0-9]*; do
        [ -r "$dir/comm" ] || continue
        if [ "$(cat "$dir/comm" 2>/dev/null)" = "samp-npc" ]; then
            kill -KILL "${dir#/proc/}" 2>/dev/null
        fi
    done
}

./samp03svr &
SAMP_PID=$!

apagar() {
    trap '' INT TERM
    kill -INT "$SAMP_PID" 2>/dev/null
    for _ in $(seq 1 "$STOP_TIMEOUT"); do
        kill -0 "$SAMP_PID" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$SAMP_PID" 2>/dev/null; then
        echo "[start] samp03svr no respondio en ${STOP_TIMEOUT}s: se fuerza el cierre"
        kill -KILL "$SAMP_PID" 2>/dev/null
    fi
    matar_npcs
    wait "$SAMP_PID" 2>/dev/null
    exit 0
}

trap apagar INT TERM

wait "$SAMP_PID"
CODE=$?
matar_npcs
if [ "$CODE" -gt 128 ]; then
    echo "[start] samp03svr termino por la senal $(( CODE - 128 ))"
fi
exit "$CODE"
STARTSH
chmod 755 "$SERVER/start.sh"

echo "  start.sh escrito"
chown -R root:root "$SERVER"
grep -iE "^(port|sv_port|plugins|filterscripts|maxplayers|hostname)" "$CFG" || true
echo "Instalacion terminada"
