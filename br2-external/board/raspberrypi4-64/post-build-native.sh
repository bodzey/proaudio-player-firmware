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

# Pure-PipeWire firmware has no PulseAudio compatibility runtime. PipeWire
# remains the only audio server; ALSA compatibility PCMs route legacy media
# engines into the native PipeWire graph. PipeWire itself installs its Pulse
# protocol daemon/config unconditionally, so prune every compatibility artifact
# from the appliance target after package installation.
rm -f \
	"$TARGET_DIR/usr/bin/pulseaudio" \
	"$TARGET_DIR/usr/bin/pipewire-pulse" \
	"$TARGET_DIR/usr/bin/pactl" \
	"$TARGET_DIR/usr/bin/pacat" \
	"$TARGET_DIR/usr/bin/parec" \
	"$TARGET_DIR/usr/bin/paplay" \
	"$TARGET_DIR/usr/bin/pamon" \
	"$TARGET_DIR/usr/lib/systemd/system/pulseaudio.service" \
	"$TARGET_DIR/usr/lib/systemd/system/pipewire-pulse.service" \
	"$TARGET_DIR/usr/lib/systemd/system/pipewire-pulse.socket" \
	"$TARGET_DIR/usr/lib/systemd/user/pipewire-pulse.service" \
	"$TARGET_DIR/usr/lib/systemd/user/pipewire-pulse.socket" \
	"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/pulseaudio.service" \
	"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/pipewire-pulse.service" \
	"$TARGET_DIR/etc/systemd/system/sockets.target.wants/pipewire-pulse.socket" \
	"$TARGET_DIR/usr/share/pipewire/pipewire-pulse.conf" \
	"$TARGET_DIR/usr/share/dbus-1/system.d/pulseaudio-system.conf"
rm -rf \
	"$TARGET_DIR/usr/share/pipewire/pipewire-pulse.conf.avail" \
	"$TARGET_DIR/etc/pipewire/pipewire-pulse.conf.d" \
	"$TARGET_DIR/etc/systemd/system/pipewire-pulse.service.d"
for pulse_modules in "$TARGET_DIR"/usr/lib/pulse-*/modules; do
	[ -e "$pulse_modules" ] || continue
	rm -rf "$pulse_modules"
done

# These PipeWire components are not part of the embedded audio appliance:
# video/test generators, FFmpeg SPA helpers and RAOP sender/discovery modules.
# DLNA keeps its own GStreamer/FFmpeg stack and AirPlay reception is provided
# by Shairport Sync, so none of these are required by the player runtime.
rm -f \
	"$TARGET_DIR/usr/lib/spa-0.2/audiotestsrc/libspa-audiotestsrc.so" \
	"$TARGET_DIR/usr/lib/spa-0.2/ffmpeg/libspa-ffmpeg.so" \
	"$TARGET_DIR/usr/lib/spa-0.2/videoconvert/libspa-videoconvert.so" \
	"$TARGET_DIR/usr/lib/spa-0.2/videotestsrc/libspa-videotestsrc.so" \
	"$TARGET_DIR/usr/lib/pipewire-0.3/libpipewire-module-raop-discover.so" \
	"$TARGET_DIR/usr/lib/pipewire-0.3/libpipewire-module-raop-sink.so"

# Avahi is required for mDNS/Bonjour advertising, but avahi-dnsconfd is a
# separate DNS-configuration helper. systemd-resolved owns DNS policy here.
rm -f \
	"$TARGET_DIR/usr/sbin/avahi-dnsconfd" \
	"$TARGET_DIR/etc/avahi/avahi-dnsconfd.action" \
	"$TARGET_DIR/usr/lib/systemd/system/avahi-dnsconfd.service" \
	"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/avahi-dnsconfd.service"

# No player service requires network-online.target. NetworkManager/networkd
# converge independently and long-running receivers already restart/recover.
rm -f \
	"$TARGET_DIR/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service" \
	"$TARGET_DIR/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

# A libpulse ABI in the final rootfs means some package has silently reintroduced
# Pulse. Fail the image build instead of shipping a half-migrated appliance.
if find "$TARGET_DIR/usr/lib" -maxdepth 2 -type f -name 'libpulse*.so*' -print -quit 2>/dev/null | grep -q .; then
	echo "ERROR: libpulse reappeared in pure-PipeWire target rootfs" >&2
	find "$TARGET_DIR/usr/lib" -maxdepth 2 -type f -name 'libpulse*.so*' -print >&2 || true
	exit 1
fi

# PipeWire 1.6.x builds the Pulse protocol frontend even when libpulse support is
# disabled. The appliance must not ship any of that compatibility surface.
if find "$TARGET_DIR" -name 'pipewire-pulse*' -print -quit 2>/dev/null | grep -q .; then
	echo "ERROR: pipewire-pulse compatibility artifacts remain in pure-PipeWire target rootfs" >&2
	find "$TARGET_DIR" -name 'pipewire-pulse*' -print >&2 || true
	exit 1
fi

# Native meters depend on pw-record. Buildroot enables pw-cat/pw-record when
# libsndfile is selected; make that an explicit image invariant.
if [ ! -x "$TARGET_DIR/usr/bin/pw-record" ]; then
	echo "ERROR: pw-record is missing from pure-PipeWire target rootfs" >&2
	exit 1
fi

# Alert credentials are mutable appliance state and live on the persistent DATA
# partition. Do not leave the obsolete immutable /etc token from older images.
rm -f "$TARGET_DIR/etc/proaudio-player-alert/alerts-token"

# Embed deterministic source/version identity in every test image.
REPO_ROOT="$(CDPATH= cd -- "$BR2_EXTERNAL_PROAUDIO_PATH/.." && pwd -P)"
sh "$REPO_ROOT/scripts/release-info.sh" "$REPO_ROOT" > "$TARGET_DIR/etc/proaudio-release"
. "$TARGET_DIR/etc/proaudio-release"
printf 'ProAudio Player %s [%s/%s] build %s\n' \
	"$PROAUDIO_VERSION" "$PROAUDIO_CHANNEL" "$PROAUDIO_STATUS" "$PROAUDIO_BUILD_ID" \
	> "$TARGET_DIR/etc/issue"

# Ensure the native service is the only ProAudio control-plane daemon enabled.
if [ -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-player-native.service" ]; then
	mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
	ln -sf /usr/lib/systemd/system/proaudio-player-native.service \
		"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-player-native.service"
fi
