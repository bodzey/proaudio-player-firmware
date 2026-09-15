#!/bin/sh
set -eu

TARGET_DIR="$1"

# Native firmware must not accidentally start stale Python control-plane units
# when reusing an output directory created by the regular/4STREAM dev firmware.
for unit in \
	proaudio-player-alert.service \
	proaudio-player-webui.service \
	proaudio-player-arbiter.service
do
	rm -f "$TARGET_DIR/usr/lib/systemd/system/$unit"
	rm -f "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/$unit"
done

for binary in \
	proaudio-player-alert \
	proaudio-player-webui \
	proaudio-player-arbiter
do
	rm -f "$TARGET_DIR/usr/bin/$binary"
done

# PulseAudio is present only for libpulse client compatibility. pipewire-pulse
# is the actual server, so PulseAudio's system-bus policy is unused and refers
# to a `pulse` account that is intentionally not created without the PA daemon.
rm -f "$TARGET_DIR/usr/share/dbus-1/system.d/pulseaudio-system.conf"

# Alert credentials are mutable appliance state and live on the persistent DATA
# partition. Do not leave the obsolete immutable /etc token from older images.
rm -f "$TARGET_DIR/etc/proaudio-player-alert/alerts-token"

# Ensure the native service is the only ProAudio control-plane daemon enabled.
if [ -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-player-native.service" ]; then
	mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
	ln -sf /usr/lib/systemd/system/proaudio-player-native.service \
		"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-player-native.service"
fi
