#!/bin/bash
set -euo pipefail

SERVER=/mnt/server
CFG="$SERVER/server.cfg"

SAMP_URL="https://raw.githubusercontent.com/KrustyKoyle/files.sa-mp.com-Archive/master/samp037svr_R2-1.tar.gz"
SAMP_SHA256="f8ead0b15683fc34f13a7a84ba9ea7252b17c5e3161d8255364e1abedd697a53"
MYSQL_URL="https://github.com/pBlueG/SA-MP-MySQL/releases/download/R41-4/mysql-R41-4-Debian-static.tar.gz"
MYSQL_SHA256="2e24aabfb7d674a454961e341a7df219f65069d273c44d4323e5199a59f135be"

echo "[1/5] Dependencies"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates unzip tar file >/dev/null

mkdir -p "$SERVER"
cd /tmp

echo "[2/5] SA-MP 0.3.7-R2 server"
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
    echo "  server installed"
else
    echo "  samp03svr already present, keeping it"
    [ -f "$CFG" ] || printf 'echo Executing Server Config...\n' > "$CFG"
fi

sed -i 's/\r$//' "$CFG"
chmod 755 "$SERVER/samp03svr" "$SERVER/samp-npc" "$SERVER/announce" 2>/dev/null || true

ensure_key() {
    grep -qiE "^$1([[:space:]]|$)" "$CFG" || printf '%s %s\n' "$1" "$2" >> "$CFG"
}

set_key() {
    local key="$1" value="$2" line found=0
    [ -n "$value" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$key "*|"$key	"*|"$key")
                printf '%s %s\n' "$key" "$value"
                found=1
                ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$CFG" > "$CFG.tmp"
    [ "$found" = 1 ] || printf '%s %s\n' "$key" "$value" >> "$CFG.tmp"
    mv "$CFG.tmp" "$CFG"
}

set_key port "${SERVER_PORT:-7777}"
set_key maxplayers "${MAX_PLAYERS:-50}"
set_key rcon_password "${RCON_PASS:-}"
set_key hostname "${SERVER_NAME:-}"
ensure_key rcon_password changeme
ensure_key hostname "SA-MP Server"
ensure_key announce 0
ensure_key query 1

echo "[3/5] MySQL plugin"
if [ "${INSTALL_MYSQL:-0}" = "1" ] || [ "${INSTALL_MYSQL:-0}" = "true" ]; then
    if [ -f "$SERVER/plugins/mysql.so" ]; then
        echo "  mysql.so already present, keeping it"
    elif curl -fsSL --retry 3 --connect-timeout 20 -o mysql.tar.gz "$MYSQL_URL" && echo "$MYSQL_SHA256  mysql.tar.gz" | sha256sum -c -; then
        rm -rf mysqlplugin && mkdir -p mysqlplugin
        tar -xzf mysql.tar.gz -C mysqlplugin
        SO="$(find mysqlplugin -name 'mysql_static.so' -o -name 'mysql.so' | head -1)"
        LOGCORE="$(find mysqlplugin -name 'log-core.so' | head -1)"
        if [ -n "$SO" ]; then
            mkdir -p "$SERVER/plugins"
            install -m 644 "$SO" "$SERVER/plugins/mysql.so"
            [ -n "$LOGCORE" ] && install -m 644 "$LOGCORE" "$SERVER/log-core.so"
            echo "  mysql.so installed"
        else
            echo "  warning: no mysql.so inside the package"
        fi
    else
        echo "  warning: could not download the MySQL plugin"
    fi
else
    echo "  skipped"
fi

echo "[4/5] SampVoice 3.1 with a fixed voice port"
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

    set_key sv_port "${SV_PORT:-}"
    ensure_key sv_port ""

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
    echo "  voice module installed (sv_port = ${SV_PORT:-not set})"
else
    echo "  skipped"
fi

echo "[5/5] Startup wrapper and permissions"
cat > "$SERVER/start.sh" <<'STARTSH'
#!/bin/bash
cd /home/container || exit 1

STOP_TIMEOUT="${STOP_TIMEOUT:-30}"
case "$STOP_TIMEOUT" in
    ""|*[!0-9]*) STOP_TIMEOUT=30 ;;
esac
[ "$STOP_TIMEOUT" -lt 5 ] && STOP_TIMEOUT=5
[ "$STOP_TIMEOUT" -gt 300 ] && STOP_TIMEOUT=300

kill_npcs() {
    for dir in /proc/[0-9]*; do
        [ -r "$dir/comm" ] || continue
        if [ "$(cat "$dir/comm" 2>/dev/null)" = "samp-npc" ]; then
            kill -KILL "${dir#/proc/}" 2>/dev/null
        fi
    done
}

./samp03svr &
SAMP_PID=$!

shutdown_server() {
    trap '' INT TERM
    kill -INT "$SAMP_PID" 2>/dev/null
    for _ in $(seq 1 "$STOP_TIMEOUT"); do
        kill -0 "$SAMP_PID" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$SAMP_PID" 2>/dev/null; then
        echo "[start] samp03svr did not stop within ${STOP_TIMEOUT}s, forcing shutdown"
        kill -KILL "$SAMP_PID" 2>/dev/null
    fi
    kill_npcs
    wait "$SAMP_PID" 2>/dev/null
    exit 0
}

trap shutdown_server INT TERM

wait "$SAMP_PID"
CODE=$?
kill_npcs
if [ "$CODE" -gt 128 ]; then
    echo "[start] samp03svr exited on signal $(( CODE - 128 ))"
fi
exit "$CODE"
STARTSH
chmod 755 "$SERVER/start.sh"

echo "  start.sh written"
chown -R root:root "$SERVER"
grep -iE "^(port|sv_port|plugins|filterscripts|maxplayers|hostname)" "$CFG" || true
echo "Installation finished"
