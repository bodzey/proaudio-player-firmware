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

append_rebuild_component() {
    local candidate="$1"
    local existing
    for existing in "${rebuild_components[@]}"; do
        [[ "$existing" == "$candidate" ]] && return
    done
    rebuild_components+=("$candidate")
}

usage() {
    cat <<'EOF'
Usage: ./scripts/build.sh [options]

Options:
  --profile rpi4-native|qemu-aarch64  Select the firmware profile.
  -j, --jobs NUMBER                   Parallel build jobs (default: host CPU count).
  -o, --output DIRECTORY              Use a separate Buildroot output directory.
  --rebuild native|webui|network      Rebuild a changed local component; repeatable.
  --clean                             Discard all output/config and rebuild from scratch.
  --configure-only                    Load defconfig but do not build the image.
  --no-submodules                     Do not update Buildroot or latest dev sources.
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
            append_rebuild_component "$2"; shift
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
    "$ROOT_DIR/scripts/sync-dev-submodules.sh"
fi

"$ROOT_DIR/scripts/check-build-host.sh"

make_args=(-C "$BUILDROOT_DIR" "BR2_EXTERNAL=$BR2_EXTERNAL_DIR")
if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
    make_args+=("O=$OUTPUT_DIR")
    images_dir="$OUTPUT_DIR/images"
    fallback_lock_file="${OUTPUT_DIR}.proaudio-build.lock"
    state_file="$OUTPUT_DIR/.proaudio-source-revisions"
    config_file="$OUTPUT_DIR/.config"
else
    images_dir="$BUILDROOT_DIR/output/images"
    fallback_lock_file="$ROOT_DIR/.proaudio-build.lock"
    state_file="$BUILDROOT_DIR/output/.proaudio-source-revisions"
    config_file="$BUILDROOT_DIR/.config"
fi
had_existing_config=0
[[ -f "$config_file" ]] && had_existing_config=1

if git_dir="$(git -C "$ROOT_DIR" rev-parse --absolute-git-dir 2>/dev/null)"; then
    lock_file="$git_dir/proaudio-build.lock"
else
    lock_file="$fallback_lock_file"
fi
mkdir -p "$(dirname "$lock_file")"

command -v flock >/dev/null 2>&1 || {
    echo "flock is required to prevent concurrent Buildroot writes." >&2
    exit 1
}
exec 9>"$lock_file"
flock -n 9 || { echo "Another ProAudio firmware build is already using this output." >&2; exit 1; }

native_revision=""
webui_revision=""
network_revision=""
if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    native_source_revision="$(git -C "$ROOT_DIR/sources/proaudio-player-native" rev-parse HEAD 2>/dev/null || true)"
    native_package_revision="$(git -C "$ROOT_DIR" rev-parse HEAD:br2-external/package/proaudio-player-native 2>/dev/null || true)"
    shared_package_revision="$(git -C "$ROOT_DIR" rev-parse HEAD:br2-external/package/proaudio-player 2>/dev/null || true)"
    webui_source_revision="$(git -C "$ROOT_DIR/sources/proaudio-player-webui" rev-parse HEAD 2>/dev/null || true)"
    webui_package_revision="$(git -C "$ROOT_DIR" rev-parse HEAD:br2-external/package/proaudio-webui 2>/dev/null || true)"
    network_revision="$(git -C "$ROOT_DIR" rev-parse HEAD:br2-external/package/proaudio-networkd 2>/dev/null || true)"
    native_revision="${native_source_revision}:${native_package_revision}:${shared_package_revision}"
    webui_revision="${webui_source_revision}:${webui_package_revision}"
fi

if ((!CLEAN && had_existing_config)); then
    previous_native="$(sed -n 's/^native=//p' "$state_file" 2>/dev/null || true)"
    previous_webui="$(sed -n 's/^webui=//p' "$state_file" 2>/dev/null || true)"
    previous_network="$(sed -n 's/^network=//p' "$state_file" 2>/dev/null || true)"

    # An existing output without our state file predates this wrapper. Rebuild
    # the two local-source packages once to establish a trustworthy baseline.
    if [[ -n "$native_revision" && ( -z "$previous_native" || "$previous_native" != "$native_revision" ) ]]; then
        append_rebuild_component native
    fi
    if [[ -n "$webui_revision" && ( -z "$previous_webui" || "$previous_webui" != "$webui_revision" ) ]]; then
        append_rebuild_component webui
    fi
    if [[ -n "$network_revision" && ( -z "$previous_network" || "$previous_network" != "$network_revision" ) ]]; then
        append_rebuild_component network
    fi
fi

if ((CLEAN)); then
    printf '%s\n' "Removing all Buildroot output and configuration by explicit request..."
    make "${make_args[@]}" distclean
fi

printf 'Loading profile: %s (%s)\n' "$PROFILE" "$defconfig"
make "${make_args[@]}" "$defconfig"

# Buildroot exposes this target only after a configuration has been loaded.
# It performs Buildroot's authoritative version and behaviour checks without
# compiling firmware packages.
make -s "${make_args[@]}" dependencies
printf '%s\n' "Buildroot dependency check: OK"

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

mkdir -p "$(dirname "$state_file")"
state_tmp="$(mktemp "${state_file}.XXXXXX")"
trap 'unlink "$state_tmp" 2>/dev/null || true' EXIT
{
    printf 'native=%s\n' "$native_revision"
    printf 'webui=%s\n' "$webui_revision"
    printf 'network=%s\n' "$network_revision"
} >"$state_tmp"
mv -f "$state_tmp" "$state_file"
trap - EXIT

printf 'Firmware images: %s\n' "$images_dir"
