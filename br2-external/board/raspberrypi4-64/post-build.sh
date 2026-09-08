#!/bin/sh
set -eu

TARGET_DIR="$1"

# Remove obsolete files that Buildroot overlays do not delete during incremental builds.
rm -f "$TARGET_DIR/etc/udev/rules.d/10-proaudio-usb-storage-only.rules"
