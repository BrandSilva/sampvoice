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
