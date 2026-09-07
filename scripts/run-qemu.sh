#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$HOME/build/proaudio-qemu}"
IMAGES_DIR="$BUILD_DIR/images"

KERNEL="$IMAGES_DIR/Image"
ROOTFS="$IMAGES_DIR/rootfs.ext4"

if [[ ! -f "$KERNEL" ]]; then
    echo "Kernel image not found: $KERNEL" >&2
    exit 1
fi

if [[ ! -e "$ROOTFS" ]]; then
    echo "Root filesystem not found: $ROOTFS" >&2
    exit 1
fi

exec qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a53 \
    -nographic \
    -smp 1 \
    -kernel "$KERNEL" \
    -append "rootwait root=/dev/vda console=ttyAMA0" \
    -netdev user,id=eth0 \
    -device virtio-net-device,netdev=eth0 \
    -drive file="$ROOTFS",if=none,format=raw,id=hd0 \
    -device virtio-blk-device,drive=hd0
