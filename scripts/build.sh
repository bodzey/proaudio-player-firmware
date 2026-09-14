#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILDROOT_DIR="${BUILDROOT_DIR:-$ROOT_DIR/upstream/buildroot}"
BR2_EXTERNAL_DIR="${BR2_EXTERNAL_DIR:-$ROOT_DIR/br2-external}"
PROFILE="${PROAUDIO_BUILD_PROFILE:-rpi4-native}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')}"
OUTPUT_DIR="${OUTPUT_DIR:-}"
UPDATE_SUBMODULES=1
CLEAN=0
CONFIGURE_ONLY=0
rebuild_components=()

usage() {
    cat <<'EOF'
Usage: ./scripts/build.sh [options]

Options:
  --profile rpi4-native|qemu-aarch64  Select the firmware profile.
  -j, --jobs NUMBER                   Parallel build jobs (default: host CPU count).
  -o, --output DIRECTORY              Use a separate Buildroot output directory.
  --rebuild native|webui|network      Rebuild a changed local component; repeatable.
  --clean                             Explicitly discard Buildroot output before building.
  --configure-only                    Load defconfig but do not build the image.
  --no-submodules                     Do not synchronize/update pinned submodules.
  -h, --help                          Show this help.

The default build is incremental. --clean is never implied.
EOF
}

while (($#)); do
    case "$1" in
        --profile)
            (($# >= 2)) || { echo "--profile requires a value" >&2; exit 2; }
            PROFILE="$2"; shift
            ;;
        -j|--jobs)
            (($# >= 2)) || { echo "$1 requires a value" >&2; exit 2; }
            JOBS="$2"; shift
            ;;
        -o|--output)
            (($# >= 2)) || { echo "$1 requires a value" >&2; exit 2; }
            OUTPUT_DIR="$2"; shift
            ;;
        --rebuild)
            (($# >= 2)) || { echo "--rebuild requires a value" >&2; exit 2; }
            rebuild_components+=("$2"); shift
            ;;
        --clean) CLEAN=1 ;;
        --configure-only) CONFIGURE_ONLY=1 ;;
        --no-submodules) UPDATE_SUBMODULES=0 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "Jobs must be a positive integer." >&2; exit 2; }

case "$PROFILE" in
    rpi4-native) defconfig=proaudio_rpi4_64_native_defconfig ;;
    qemu-aarch64) defconfig=proaudio_qemu_aarch64_defconfig ;;
    *) printf 'Unknown profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

if ((CLEAN && ${#rebuild_components[@]})); then
    echo "--clean and --rebuild cannot be used together." >&2
    exit 2
fi
if ((CONFIGURE_ONLY && ${#rebuild_components[@]})); then
    echo "--configure-only and --rebuild cannot be used together." >&2
    exit 2
fi

if ((UPDATE_SUBMODULES)); then
    git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        echo "The repository is not a Git checkout." >&2
        exit 1
    }
    git -C "$ROOT_DIR" submodule sync --recursive
    # Deliberately omit --remote: the firmware commit's gitlinks are authoritative.
    git -C "$ROOT_DIR" submodule update --init --recursive
fi

"$ROOT_DIR/scripts/check-build-host.sh"

make_args=(-C "$BUILDROOT_DIR" "BR2_EXTERNAL=$BR2_EXTERNAL_DIR")
if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
    make_args+=("O=$OUTPUT_DIR")
    images_dir="$OUTPUT_DIR/images"
    lock_file="${OUTPUT_DIR}.proaudio-build.lock"
else
    images_dir="$BUILDROOT_DIR/output/images"
    lock_file="$BUILDROOT_DIR/.proaudio-build.lock"
fi

command -v flock >/dev/null 2>&1 || {
    echo "flock is required to prevent concurrent Buildroot writes." >&2
    exit 1
}
exec 9>"$lock_file"
flock -n 9 || { echo "Another ProAudio firmware build is already using this output." >&2; exit 1; }

if ((CLEAN)); then
    printf '%s\n' "Cleaning Buildroot output by explicit request..."
    make "${make_args[@]}" clean
fi

printf 'Loading profile: %s (%s)\n' "$PROFILE" "$defconfig"
make "${make_args[@]}" "$defconfig"

if ((CONFIGURE_ONLY)); then
    printf '%s\n' "Configuration updated; build skipped by request."
    exit 0
fi

for component in "${rebuild_components[@]}"; do
    case "$component" in
        native) package_target=proaudio-player-native-dirclean ;;
        webui) package_target=proaudio-webui-dirclean ;;
        network) package_target=proaudio-networkd-dirclean ;;
        *) printf 'Unknown rebuild component: %s\n' "$component" >&2; exit 2 ;;
    esac
    printf 'Refreshing component: %s\n' "$component"
    make "${make_args[@]}" "$package_target"
done

printf 'Building with %s job(s)...\n' "$JOBS"
make -j"$JOBS" "${make_args[@]}"
printf 'Firmware images: %s\n' "$images_dir"
