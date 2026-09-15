#!/bin/sh
set -eu

TARGET_DIR="$1"

# Remove obsolete files that Buildroot overlays do not delete during
# incremental builds.
rm -f "$TARGET_DIR/etc/udev/rules.d/10-proaudio-usb-storage-only.rules"
rm -f "$TARGET_DIR/etc/udev/rules.d/10-proaudio-usb-allowlist.rules"
rm -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-player-web.service"
rm -f "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-player-web.service"
rm -f "$TARGET_DIR/usr/bin/proaudio-player-web"
rm -f "$TARGET_DIR/usr/lib/systemd/system/proaudio-grow-rootfs.service"
rm -f "$TARGET_DIR/usr/libexec/proaudio-player/grow-rootfs"
rm -f "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-grow-rootfs.service"
rm -rf "$TARGET_DIR/var/lib/proaudio-storage-grow"

# Older firmware builds represented persistent application paths as symlinks
# into /data. Remove only those stale symlinks when reusing an output tree.
# Buildroot must see normal directories while creating users/rootfs; systemd
# bind mounts attach the persistent DATA directories at boot.
for path in \
	"$TARGET_DIR/srv/music" \
	"$TARGET_DIR/var/lib/proaudio-player" \
	"$TARGET_DIR/var/lib/proaudio-player-alert"
do
	if [ -L "$path" ]; then
		rm -f "$path"
	fi
done

mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
rm -f "$TARGET_DIR/etc/systemd/system/local-fs.target.wants/data.mount"
ln -sf /usr/lib/systemd/system/proaudio-storage.service \
	"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/proaudio-storage.service"

# DEV firmware: make SSH available immediately after networking comes up.
if [ -f "$TARGET_DIR/usr/lib/systemd/system/sshd.service" ]; then
	ln -sf /usr/lib/systemd/system/sshd.service \
		"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/sshd.service"
fi
