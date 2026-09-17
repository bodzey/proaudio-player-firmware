#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
: "${HOME:?HOME must be set}"
BUILD_DIR="${BUILD_DIR:-${PROAUDIO_QEMU_OUTPUT:-$HOME/build/proaudio-qemu}}"
IMAGES_DIR="$BUILD_DIR/images"
KERNEL="$IMAGES_DIR/Image"
ROOTFS="$IMAGES_DIR/rootfs.ext4"
WEB_PORT="${QEMU_WEB_PORT:-18080}"
MEMORY_MB="${QEMU_MEMORY_MB:-1024}"
SMP="${QEMU_SMP:-2}"
NET_MODE="${QEMU_NET_MODE:-user}"
SNAPSHOT="${QEMU_SNAPSHOT:-1}"

[[ "$WEB_PORT" =~ ^[1-9][0-9]*$ ]] && ((WEB_PORT <= 65535)) || {
    echo "QEMU_WEB_PORT must be an integer from 1 to 65535" >&2
    exit 2
}
[[ "$MEMORY_MB" =~ ^[1-9][0-9]*$ ]] || { echo "QEMU_MEMORY_MB must be positive" >&2; exit 2; }
[[ "$SMP" =~ ^[1-9][0-9]*$ ]] || { echo "QEMU_SMP must be positive" >&2; exit 2; }
[[ "$SNAPSHOT" == 0 || "$SNAPSHOT" == 1 ]] || { echo "QEMU_SNAPSHOT must be 0 or 1" >&2; exit 2; }

if [[ ! -f "$KERNEL" ]]; then
    echo "Kernel image not found: $KERNEL" >&2
    echo "Build it first with: ./scripts/build.sh --profile qemu-aarch64" >&2
    exit 1
fi
if [[ ! -e "$ROOTFS" ]]; then
    echo "Root filesystem not found: $ROOTFS" >&2
    echo "Build it first with: ./scripts/build.sh --profile qemu-aarch64" >&2
    exit 1
fi

QEMU_BIN="${QEMU_BIN:-}"
if [[ -z "$QEMU_BIN" && -x "$BUILD_DIR/host/bin/qemu-system-aarch64" ]]; then
    QEMU_BIN="$BUILD_DIR/host/bin/qemu-system-aarch64"
fi
if [[ -z "$QEMU_BIN" ]]; then
    QEMU_BIN="$(command -v qemu-system-aarch64 || true)"
fi
[[ -n "$QEMU_BIN" && -x "$QEMU_BIN" ]] || {
    echo "qemu-system-aarch64 was not found." >&2
    echo "Run ./scripts/bootstrap-build-host.sh --with-qemu or build the QEMU profile first." >&2
    exit 1
}

net_args=()
case "$NET_MODE" in
    user)
        net_args=(
            -netdev "user,id=eth0,hostfwd=tcp:127.0.0.1:${WEB_PORT}-:8080"
            -device virtio-net-device,netdev=eth0
        )
        ;;
    tap)
        : "${QEMU_TAP_IF:?QEMU_TAP_IF must name an existing TAP interface when QEMU_NET_MODE=tap}"
        net_args=(
            -netdev "tap,id=eth0,ifname=${QEMU_TAP_IF},script=no,downscript=no"
            -device virtio-net-device,netdev=eth0
        )
        ;;
    *)
        echo "QEMU_NET_MODE must be 'user' or 'tap'" >&2
        exit 2
        ;;
esac

snapshot_args=()
if [[ "$SNAPSHOT" == 1 ]]; then
    snapshot_args=(-snapshot)
fi

printf 'Starting ProAudio Player QEMU from %s\n' "$BUILD_DIR" >&2
if [[ "$NET_MODE" == user ]]; then
    printf 'Web UI/API: http://127.0.0.1:%s/\n' "$WEB_PORT" >&2
    printf '%s\n' 'User-mode networking is for UI/API/runtime smoke tests; use QEMU_NET_MODE=tap for LAN multicast discovery.' >&2
fi
printf '%s\n' 'QEMU console: Ctrl-A X exits the emulator.' >&2

exec "$QEMU_BIN" \
    -M virt \
    -cpu cortex-a53 \
    -nographic \
    -m "$MEMORY_MB" \
    -smp "$SMP" \
    -kernel "$KERNEL" \
    -append "rootwait root=/dev/vda rw console=ttyAMA0" \
    "${net_args[@]}" \
    -drive file="$ROOTFS",if=none,format=raw,id=hd0 \
    -device virtio-blk-device,drive=hd0 \
    "${snapshot_args[@]}"
