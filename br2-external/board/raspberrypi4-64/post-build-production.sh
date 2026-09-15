#!/bin/sh
set -eu

TARGET_DIR="$1"
KEYS_FILE=${PROAUDIO_SSH_AUTHORIZED_KEYS_FILE:-}

if [ -z "$KEYS_FILE" ]; then
	printf '%s\n' \
		"ERROR: production firmware requires PROAUDIO_SSH_AUTHORIZED_KEYS_FILE." \
		"Set it to a readable OpenSSH public-key file, for example:" \
		"  PROAUDIO_SSH_AUTHORIZED_KEYS_FILE=\"\$HOME/.ssh/id_ed25519.pub\" ./scripts/build.sh --clean" >&2
	exit 1
fi

if [ ! -r "$KEYS_FILE" ]; then
	printf 'ERROR: SSH authorized-keys file is not readable: %s\n' "$KEYS_FILE" >&2
	exit 1
fi

if ! grep -Eq '^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521))[[:space:]]' "$KEYS_FILE"; then
	printf 'ERROR: no supported OpenSSH public key found in %s\n' "$KEYS_FILE" >&2
	exit 1
fi

install -d -m 0700 "$TARGET_DIR/root/.ssh"
install -m 0600 "$KEYS_FILE" "$TARGET_DIR/root/.ssh/authorized_keys"

# Defense in depth: production has no local login/debug console even if a
# future package or preset attempts to enable one.
mkdir -p "$TARGET_DIR/etc/systemd/system"
ln -sf /dev/null "$TARGET_DIR/etc/systemd/system/debug-shell.service"
ln -sf /dev/null "$TARGET_DIR/etc/systemd/system/getty@tty1.service"
ln -sf /dev/null "$TARGET_DIR/etc/systemd/system/serial-getty@ttyAMA0.service"

rm -f \
	"$TARGET_DIR/etc/systemd/system/getty.target.wants/getty@tty1.service" \
	"$TARGET_DIR/etc/systemd/system/getty.target.wants/serial-getty@ttyAMA0.service" \
	"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/debug-shell.service"
