#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
IMAGE="${PROAUDIO_BUILD_IMAGE:-proaudio-player-buildroot:bookworm}"
RUNTIME="${CONTAINER_RUNTIME:-}"

usage() {
    cat <<'EOF'
Usage: ./scripts/build-container.sh [build.sh options]

Builds in a controlled Debian container while keeping Buildroot output and
downloads in the repository. Docker or Podman is required on the host.
EOF
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    usage
    "$ROOT_DIR/scripts/build.sh" --help
    exit 0
fi

if ((EUID == 0)); then
    echo "Run container builds as a regular user so generated files keep safe ownership." >&2
    exit 1
fi

if [[ -z "$RUNTIME" ]]; then
    if command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    else
        echo "Docker or Podman is required." >&2
        exit 1
    fi
fi
command -v "$RUNTIME" >/dev/null 2>&1 || { echo "$RUNTIME is unavailable." >&2; exit 1; }

[[ -d "$ROOT_DIR/.git" ]] || { echo "The repository is not a Git checkout." >&2; exit 1; }
git -C "$ROOT_DIR" submodule sync --recursive
git -C "$ROOT_DIR" submodule update --init --recursive

"$RUNTIME" build \
    --file "$ROOT_DIR/containers/Dockerfile.build" \
    --tag "$IMAGE" \
    "$ROOT_DIR/containers"

run_args=(
    run --rm --init
    --user "$(id -u):$(id -g)"
    --env HOME=/tmp
    --volume "$ROOT_DIR:/workspace"
    --workdir /workspace
)
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
    run_args+=(--security-opt label=disable)
fi

exec "$RUNTIME" "${run_args[@]}" "$IMAGE" "$@"
