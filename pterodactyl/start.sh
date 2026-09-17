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
