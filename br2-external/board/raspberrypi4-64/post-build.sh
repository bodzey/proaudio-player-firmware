#!/bin/sh
set -eu

TARGET_DIR="$1"

# Remove obsolete files that Buildroot overlays do not delete during incremental builds.
rm -f "$TARGET_DIR/etc/udev/rules.d/10-proaudio-usb-storage-only.rules"
rm -f "$TARGET_DIR/etc/udev/rules.d/10-proaudio-usb-allowlist.rules"
rm -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-player-web.service"
rm -f "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-player-web.service"
rm -f "$TARGET_DIR/usr/bin/proaudio-player-web"

# DEV firmware: make SSH available immediately after networking comes up.
if [ -f "$TARGET_DIR/usr/lib/systemd/system/sshd.service" ]; then
	mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
	ln -sf /usr/lib/systemd/system/sshd.service \
		"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/sshd.service"
fi
