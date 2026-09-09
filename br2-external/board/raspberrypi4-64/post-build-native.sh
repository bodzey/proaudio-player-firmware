#!/bin/sh
set -eu

TARGET_DIR="$1"

# Native firmware must not accidentally start stale Python control-plane units
# when reusing an output directory created by the regular dev firmware.
for unit in proaudio-player-alert.service proaudio-player-webui.service; do
	rm -f "$TARGET_DIR/usr/lib/systemd/system/$unit"
	rm -f "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/$unit"
done

rm -f "$TARGET_DIR/usr/bin/proaudio-player-alert"
rm -f "$TARGET_DIR/usr/bin/proaudio-player-webui"

# Ensure the native service is the only ProAudio control-plane daemon enabled.
if [ -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-player-native.service" ]; then
	mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
	ln -sf /usr/lib/systemd/system/proaudio-player-native.service \
		"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-player-native.service"
fi
