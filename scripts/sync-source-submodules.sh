#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_PATHS=(
    upstream/buildroot
    sources/proaudio-player-native
    sources/proaudio-player-webui
)

git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "The repository is not a Git checkout." >&2
    exit 1
}

git -C "$ROOT_DIR" submodule sync --recursive

for path in "${SOURCE_PATHS[@]}"; do
    if git -C "$ROOT_DIR/$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
       [[ -n "$(git -C "$ROOT_DIR/$path" status --porcelain)" ]]; then
        printf 'Submodule %s has local changes; refusing to overwrite them.\n' "$path" >&2
        exit 1
    fi
done

# Production firmware is reproducible: every source is checked out at the
# exact gitlink recorded by the firmware commit. Never follow remote branches.
git -C "$ROOT_DIR" submodule update --init --recursive "${SOURCE_PATHS[@]}"

for path in "${SOURCE_PATHS[@]}"; do
    expected="$(git -C "$ROOT_DIR" rev-parse "HEAD:$path")"
    actual="$(git -C "$ROOT_DIR/$path" rev-parse HEAD)"
    if [[ "$actual" != "$expected" ]]; then
        printf 'Submodule %s did not reach pinned revision (%s != %s).\n' \
            "$path" "$actual" "$expected" >&2
        exit 1
    fi
    printf 'Source %s: pinned at %s\n' "$path" "${actual:0:12}"
done
