#!/bin/sh
set -eu

current_pid=""

stop_renderer() {
    if [ -n "$current_pid" ]; then
        kill "$current_pid" 2>/dev/null || true
        wait "$current_pid" 2>/dev/null || true
        current_pid=""
    fi
}

trap 'stop_renderer; exit 0' INT TERM

default_interface() {
    ip route 2>/dev/null | awk '
        $1 == "default" {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                    exit
                }
            }
        }'
}

while :; do
    interface="$(default_interface)"
    if [ -z "$interface" ]; then
        sleep 2
        continue
    fi

    /usr/bin/gmediarender \
        --interface-name="$interface" \
        --port=49494 \
        --friendly-name="ProAudio Player" \
        --gstout-audiosink=pulsesink &
    current_pid=$!

    while kill -0 "$current_pid" 2>/dev/null; do
        sleep 2
        next_interface="$(default_interface)"
        if [ "$next_interface" != "$interface" ]; then
            stop_renderer
            break
        fi
    done

    if [ -n "$current_pid" ]; then
        wait "$current_pid"
        status=$?
        current_pid=""
        exit "$status"
    fi
done
