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

# Embed deterministic source/version identity without changing the stable
# Pulse-based audio runtime carried by the main branch.
REPO_ROOT="$(CDPATH='' cd -- "$BR2_EXTERNAL_PROAUDIO_PATH/.." && pwd -P)"
RELEASE_FILE="$TARGET_DIR/etc/proaudio-release"
sh "$REPO_ROOT/scripts/release-info.sh" "$REPO_ROOT" > "$RELEASE_FILE"
PROAUDIO_VERSION="$(sed -n 's/^PROAUDIO_VERSION=//p' "$RELEASE_FILE")"
PROAUDIO_CHANNEL="$(sed -n 's/^PROAUDIO_CHANNEL=//p' "$RELEASE_FILE")"
PROAUDIO_STATUS="$(sed -n 's/^PROAUDIO_STATUS=//p' "$RELEASE_FILE")"
PROAUDIO_BUILD_ID="$(sed -n 's/^PROAUDIO_BUILD_ID=//p' "$RELEASE_FILE")"
printf 'ProAudio Player %s [%s/%s] build %s\n' \
	"$PROAUDIO_VERSION" "$PROAUDIO_CHANNEL" "$PROAUDIO_STATUS" "$PROAUDIO_BUILD_ID" \
	> "$TARGET_DIR/etc/issue"

# Ensure the native service is the only ProAudio control-plane daemon enabled.
if [ -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-player-native.service" ]; then
	mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
	ln -sf /usr/lib/systemd/system/proaudio-player-native.service \
		"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-player-native.service"
fi
