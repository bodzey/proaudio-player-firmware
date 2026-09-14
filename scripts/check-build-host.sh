#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILDROOT_DIR="${BUILDROOT_DIR:-$ROOT_DIR/upstream/buildroot}"
BR2_EXTERNAL_DIR="${BR2_EXTERNAL_DIR:-$ROOT_DIR/br2-external}"
QUIET=0
ALLOW_ROOT=0

usage() {
    cat <<'EOF'
Usage: ./scripts/check-build-host.sh [--quiet] [--allow-root]

Checks the host without installing packages or changing the repository.
EOF
}

while (($#)); do
    case "$1" in
        --quiet) QUIET=1 ;;
        --allow-root) ALLOW_ROOT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

log() {
    ((QUIET)) || printf '%s\n' "$*"
}

failures=0
fail() {
    printf 'ERROR: %s\n' "$*" >&2
    failures=$((failures + 1))
}

if [[ "$(uname -s)" != Linux ]]; then
    fail "Buildroot requires a Linux host. Use ./scripts/build-container.sh on this system."
fi

if ((EUID == 0 && !ALLOW_ROOT)); then
    fail "Do not build Buildroot as root. Run the build as a regular user."
fi

if [[ "$ROOT_DIR" =~ [[:space:]] ]]; then
    fail "The repository path contains whitespace: $ROOT_DIR"
fi

required_commands=(
    awk bash bc bison bzip2 c++ cmp cpio file find flex flock gcc git grep gzip
    ld make patch perl python3 rsync sed tar unzip wget xargs xz
)
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Missing host command: $command_name"
done

if command -v make >/dev/null 2>&1; then
    make_version="$(make --version | awk 'NR == 1 { print $3 }')"
    make_major="${make_version%%.*}"
    make_minor="${make_version#*.}"
    make_minor="${make_minor%%.*}"
    if [[ ! "$make_major" =~ ^[0-9]+$ || ! "$make_minor" =~ ^[0-9]+$ ]] || \
       ((make_major < 3 || (make_major == 3 && make_minor < 81))); then
        fail "GNU make 3.81 or newer is required (found ${make_version:-unknown})."
    fi
fi

if [[ ! -f "$BUILDROOT_DIR/Makefile" ]]; then
    fail "Buildroot submodule is not initialized: $BUILDROOT_DIR"
fi
if [[ ! -f "$BR2_EXTERNAL_DIR/external.desc" ]]; then
    fail "Invalid BR2_EXTERNAL directory: $BR2_EXTERNAL_DIR"
fi

case_probe="$(mktemp -d "$ROOT_DIR/.build-host-case-check.XXXXXX")"
trap 'rmdir "$case_probe" 2>/dev/null || true' EXIT
: >"$case_probe/lowercase"
if [[ -e "$case_probe/LOWERCASE" ]]; then
    fail "The repository filesystem is case-insensitive; Buildroot needs a case-sensitive filesystem."
fi
unlink "$case_probe/lowercase"
rmdir "$case_probe"
trap - EXIT

if ((failures)); then
    printf '\nHost check failed with %d problem(s).\n' "$failures" >&2
    printf 'Run ./scripts/bootstrap-build-host.sh or use ./scripts/build-container.sh.\n' >&2
    exit 1
fi

log "Basic host tools: OK"

available_kib="$(df -Pk "$ROOT_DIR" | awk 'NR == 2 { print $4 }')"
if [[ "$available_kib" =~ ^[0-9]+$ ]] && ((available_kib < 20 * 1024 * 1024)); then
    printf 'WARNING: less than 20 GiB is free on the build filesystem.\n' >&2
fi

log "Basic build host is ready; configuration-specific checks run during build."
