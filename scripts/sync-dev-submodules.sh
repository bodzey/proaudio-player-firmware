#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_PATHS=(
    sources/proaudio-player-native
    sources/proaudio-player-webui
)

git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "The repository is not a Git checkout." >&2
    exit 1
}

git -C "$ROOT_DIR" submodule sync --recursive

# Buildroot is part of the firmware toolchain contract. Keep its exact gitlink
# revision instead of following the remote default branch.
if git -C "$ROOT_DIR/upstream/buildroot" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
   [[ -n "$(git -C "$ROOT_DIR/upstream/buildroot" status --porcelain)" ]]; then
    echo "Buildroot submodule has local changes; refusing to overwrite them." >&2
    exit 1
fi
git -C "$ROOT_DIR" submodule update --init --recursive upstream/buildroot

for path in "${SOURCE_PATHS[@]}"; do
    branch="$(git -C "$ROOT_DIR" config -f .gitmodules --get "submodule.${path}.branch" || true)"
    if [[ "$branch" != dev ]]; then
        printf 'Submodule %s must track dev, found: %s\n' "$path" "${branch:-unset}" >&2
        exit 1
    fi

    if git -C "$ROOT_DIR/$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
       [[ -n "$(git -C "$ROOT_DIR/$path" status --porcelain)" ]]; then
        printf 'Submodule %s has local changes; refusing to overwrite them.\n' "$path" >&2
        exit 1
    fi
done

for path in "${SOURCE_PATHS[@]}"; do
    git -C "$ROOT_DIR" submodule update --init --remote --checkout "$path"

    head_revision="$(git -C "$ROOT_DIR/$path" rev-parse HEAD)"
    dev_revision="$(git -C "$ROOT_DIR/$path" rev-parse refs/remotes/origin/dev)"
    if [[ "$head_revision" != "$dev_revision" ]]; then
        printf 'Submodule %s did not reach origin/dev (%s != %s).\n' \
            "$path" "$head_revision" "$dev_revision" >&2
        exit 1
    fi
    printf 'Source %s: origin/dev at %s\n' "$path" "${head_revision:0:12}"
done
