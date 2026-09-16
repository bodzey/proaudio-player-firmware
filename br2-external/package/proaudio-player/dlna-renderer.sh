#!/bin/sh
set -eu

interface="${DLNA_INTERFACE:-proaudio-dlna}"
[ "$interface" != "lo" ] || {
    echo "DLNA: loopback не підтримується libupnp" >&2
    exit 1
}
[ -d "/sys/class/net/$interface" ] || {
    echo "DLNA: внутрішній інтерфейс $interface не створено" >&2
    exit 1
}

echo "DLNA: запуск transport worker на внутрішньому інтерфейсі $interface" >&2
exec /usr/bin/gmediarender \
    --interface-name="$interface" \
    --port=49494 \
    --friendly-name="ProAudio Player Internal Transport" \
    --gstout-audiopipe="pipewiresink target-object=proaudio_player_music" \
    --gstout-initial-volume-db=0.0 \
    --gstout-buffer-duration=0
