#!/bin/sh
set -eu

# Kept as a compatibility entry point for the Raspberry Pi profile. The native
# image finalization is hardware-neutral and shared with the QEMU target.
exec "$BR2_EXTERNAL_PROAUDIO_PATH/board/common/post-build-native.sh" "$@"
