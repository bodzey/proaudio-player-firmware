#!/bin/sh
set -eu

TARGET_DIR="$1"

# Remove obsolete files that Buildroot overlays do not delete during incremental builds.
rm -f "$TARGET_DIR/etc/udev/rules.d/10-proaudio-usb-storage-only.rules"
rm -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-player-web.service"\nrm -f "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-player-web.service"\nrm -f "$TARGET_DIR/usr/bin/proaudio-player-web"\n