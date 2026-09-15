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

# PipeWire-Pulse is the only PulseAudio-compatible server in native firmware.
# spotifyd, native and the output watcher still require libpulse and pactl, so
# retain the client ABI/tools but remove the redundant PulseAudio daemon and its
# loadable server modules from the final appliance rootfs.
rm -f "$TARGET_DIR/usr/bin/pulseaudio"
for pulse_modules in "$TARGET_DIR"/usr/lib/pulse-*/modules; do
	[ -e "$pulse_modules" ] || continue
	rm -rf "$pulse_modules"
done
rm -f "$TARGET_DIR/usr/lib/systemd/system/pulseaudio.service"
rm -f "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/pulseaudio.service"
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
