#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WITH_QEMU=0
UPDATE_SUBMODULES=1
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: ./scripts/bootstrap-build-host.sh [options]

Options:
  --with-qemu       Install the optional QEMU AArch64 emulator.
  --no-submodules   Do not initialize/update pinned Git submodules.
  -y, --yes         Pass the non-interactive confirmation flag to the package manager.
  -h, --help        Show this help.

This script installs build-host packages. It never starts a firmware build.
EOF
}

while (($#)); do
    case "$1" in
        --with-qemu) WITH_QEMU=1 ;;
        --no-submodules) UPDATE_SUBMODULES=0 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ "$(uname -s)" != Linux ]]; then
    printf '%s\n' "Native Buildroot builds require Linux. Use ./scripts/build-container.sh." >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    printf '%s\n' "Cannot identify the Linux distribution (/etc/os-release is missing)." >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
distro="${ID:-unknown}"
distro_like=" ${ID_LIKE:-} "

if ((EUID == 0)); then
    elevate=()
elif command -v sudo >/dev/null 2>&1; then
    elevate=(sudo)
else
    printf '%s\n' "sudo is unavailable. Re-run this bootstrap as root, then build as a regular user." >&2
    exit 1
fi

run_privileged() {
    "${elevate[@]}" "$@"
}

common_debian=(
    build-essential bash bc binutils bison bzip2 ca-certificates cpio file
    findutils flex gawk git gzip libncurses-dev make patch perl python3 rsync
    sed tar unzip util-linux wget which xz-utils
)
common_fedora=(
    bash bc binutils bison bzip2 ca-certificates cpio diffutils file findutils
    flex gawk gcc gcc-c++ git gzip make ncurses-devel patch perl python3 rsync
    sed tar unzip util-linux wget which xz
)
common_arch=(
    base-devel bash bc binutils bison bzip2 ca-certificates cpio file findutils
    flex gawk gcc git gzip ncurses patch perl python rsync sed tar unzip util-linux wget which xz
)
common_suse=(
    bash bc binutils bison bzip2 ca-certificates cpio diffutils file findutils
    flex gawk gcc gcc-c++ git gzip make ncurses-devel patch perl python3 rsync
    sed tar unzip util-linux wget which xz
)
common_alpine=(
    alpine-sdk bash bc binutils bison bzip2 ca-certificates cpio file findutils
    flex gawk gcc g++ git gzip make ncurses-dev patch perl python3 rsync sed tar
    unzip util-linux wget xz
)

if [[ "$distro" =~ ^(debian|ubuntu|linuxmint|pop)$ ]] || [[ "$distro_like" == *" debian "* ]]; then
    command -v apt-get >/dev/null || { echo "apt-get is unavailable" >&2; exit 1; }
    apt_flags=(install --no-install-recommends)
    ((ASSUME_YES)) && apt_flags+=(-y)
    run_privileged apt-get update
    packages=("${common_debian[@]}")
    ((WITH_QEMU)) && packages+=(qemu-system-arm)
    run_privileged apt-get "${apt_flags[@]}" "${packages[@]}"
elif [[ "$distro" =~ ^(fedora|rhel|centos|rocky|almalinux)$ ]] || [[ "$distro_like" == *" fedora "* || "$distro_like" == *" rhel "* ]]; then
    command -v dnf >/dev/null || { echo "dnf is unavailable" >&2; exit 1; }
    dnf_flags=(install)
    ((ASSUME_YES)) && dnf_flags+=(-y)
    packages=("${common_fedora[@]}")
    ((WITH_QEMU)) && packages+=(qemu-system-aarch64-core)
    run_privileged dnf "${dnf_flags[@]}" "${packages[@]}"
elif [[ "$distro" =~ ^(arch|manjaro|endeavouros)$ ]] || [[ "$distro_like" == *" arch "* ]]; then
    command -v pacman >/dev/null || { echo "pacman is unavailable" >&2; exit 1; }
    pacman_flags=(-S --needed)
    ((ASSUME_YES)) && pacman_flags+=(--noconfirm)
    packages=("${common_arch[@]}")
    ((WITH_QEMU)) && packages+=(qemu-system-aarch64)
    run_privileged pacman "${pacman_flags[@]}" "${packages[@]}"
elif [[ "$distro" =~ ^(opensuse|opensuse-leap|opensuse-tumbleweed|sles)$ ]] || [[ "$distro_like" == *" suse "* ]]; then
    command -v zypper >/dev/null || { echo "zypper is unavailable" >&2; exit 1; }
    zypper_flags=(--no-refresh)
    ((ASSUME_YES)) && zypper_flags+=(--non-interactive)
    packages=("${common_suse[@]}")
    ((WITH_QEMU)) && packages+=(qemu-arm)
    run_privileged zypper "${zypper_flags[@]}" install "${packages[@]}"
elif [[ "$distro" == alpine ]]; then
    command -v apk >/dev/null || { echo "apk is unavailable" >&2; exit 1; }
    packages=("${common_alpine[@]}")
    ((WITH_QEMU)) && packages+=(qemu-system-aarch64)
    run_privileged apk add "${packages[@]}"
else
    printf 'Unsupported distribution: %s\n' "${PRETTY_NAME:-$distro}" >&2
    printf '%s\n' "Use ./scripts/build-container.sh for a controlled Debian build host." >&2
    exit 1
fi

if ((UPDATE_SUBMODULES)); then
    if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf '%s\n' "This is not a Git checkout; cannot initialize submodules." >&2
        exit 1
    fi
    git -C "$ROOT_DIR" submodule sync --recursive
    git -C "$ROOT_DIR" submodule update --init --recursive
fi

if ((EUID == 0)); then
    "$ROOT_DIR/scripts/check-build-host.sh" --allow-root
    printf '%s\n' "Dependencies are installed. Run the firmware build as a regular user."
else
    "$ROOT_DIR/scripts/check-build-host.sh"
fi
