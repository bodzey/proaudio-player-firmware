#!/bin/bash
set -euo pipefail

BOARD_DIR="$(dirname "$0")"
GENIMAGE_CFG="${BINARIES_DIR}/genimage-proaudio.cfg"
DATA_IMAGE="${BINARIES_DIR}/data.ext4"
DATA_IMAGE_SIZE_MIB=64

FILES=()
for file in "${BINARIES_DIR}"/*.dtb "${BINARIES_DIR}"/rpi-firmware/*; do
	FILES+=( "${file#"${BINARIES_DIR}"/}" )
done

KERNEL="$(sed -n 's/^kernel=//p' "${BINARIES_DIR}/rpi-firmware/config.txt")"
FILES+=( "${KERNEL}" )

BOOT_FILES="$(printf '\\t\\t\\t\"%s\",\\n' "${FILES[@]}")"
sed "s|#BOOT_FILES#|${BOOT_FILES}|" "${BOARD_DIR}/genimage.cfg.in" > "${GENIMAGE_CFG}"

# DATA is intentionally tiny in the distributable image. The first-boot
# service grows partition 3 and this filesystem to the actual boot medium.
rm -f "${DATA_IMAGE}" "${BINARIES_DIR}/sdcard.img"
dd if=/dev/zero of="${DATA_IMAGE}" bs=1M count=0 seek="${DATA_IMAGE_SIZE_MIB}" status=none
"${HOST_DIR}/sbin/mkfs.ext4" -F -q \
	-L PROAUDIO_DATA \
	-U 50524155-4441-5441-0000-000000000001 \
	-m 1 \
	-O '^64bit' \
	-E lazy_itable_init=0,lazy_journal_init=0 \
	"${DATA_IMAGE}"

"${BR2_EXTERNAL_PROAUDIO_PATH}/../upstream/buildroot/support/scripts/genimage.sh" \
	-c "${GENIMAGE_CFG}"
