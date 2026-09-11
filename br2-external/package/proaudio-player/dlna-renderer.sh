#!/bin/sh
set -eu

# gmediarender is deliberately not the LAN-facing UPnP device. The native daemon
# owns discovery, AVTransport and RenderingControl, while this process is only the
# local decoder/transport worker. Binding to loopback prevents a duplicate renderer
# from appearing in controllers and keeps remote volume control out of GStreamer.
exec /usr/bin/gmediarender \
    --interface-name=lo \
    --port=49494 \
    --friendly-name="ProAudio Player Transport" \
    --gstout-audiosink=pulsesink \
    --gstout-initial-volume-db=0.0 \
    --gstout-buffer-duration=0
