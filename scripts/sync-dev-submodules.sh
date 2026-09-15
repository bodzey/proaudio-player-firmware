#!/usr/bin/env bash
set -Eeuo pipefail

# Backward-compatible entry point kept for existing local workflows.
# Production synchronization is branch-neutral and gitlink-pinned.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/sync-source-submodules.sh" "$@"
