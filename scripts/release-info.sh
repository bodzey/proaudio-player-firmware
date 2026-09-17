#!/bin/sh
set -eu

REPO_ROOT="${1:-$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)}"
RELEASE_CONF="$REPO_ROOT/release.conf"

config_value()
{
	key="$1"
	value="$(sed -n "s/^${key}=//p" "$RELEASE_CONF" | head -n 1)"
	[ -n "$value" ] || {
		printf 'Missing %s in %s\n' "$key" "$RELEASE_CONF" >&2
		exit 1
	}
	printf '%s\n' "$value"
}

safe_value()
{
	name="$1"
	value="$2"
	case "$value" in
		*[!0-9A-Za-z._+-]*)
			printf 'Invalid %s: %s\n' "$name" "$value" >&2
			exit 1
			;;
	esac
}

repo_sha()
{
	git -C "$1" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown\n'
}

repo_dirty()
{
	if ! git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		printf '1\n'
		return
	fi
	if [ -n "$(git -C "$1" status --porcelain --untracked-files=normal --ignore-submodules=all 2>/dev/null)" ]; then
		printf '1\n'
	else
		printf '0\n'
	fi
}

PROAUDIO_FIRMWARE_VERSION="$(config_value PROAUDIO_FIRMWARE_VERSION)"
PROAUDIO_FIRMWARE_CHANNEL="$(config_value PROAUDIO_FIRMWARE_CHANNEL)"
PROAUDIO_FIRMWARE_STATUS="$(config_value PROAUDIO_FIRMWARE_STATUS)"
safe_value PROAUDIO_FIRMWARE_VERSION "$PROAUDIO_FIRMWARE_VERSION"
safe_value PROAUDIO_FIRMWARE_CHANNEL "$PROAUDIO_FIRMWARE_CHANNEL"
safe_value PROAUDIO_FIRMWARE_STATUS "$PROAUDIO_FIRMWARE_STATUS"

FIRMWARE_SHA="$(repo_sha "$REPO_ROOT")"
NATIVE_SHA="$(repo_sha "$REPO_ROOT/sources/proaudio-player-native")"
WEBUI_SHA="$(repo_sha "$REPO_ROOT/sources/proaudio-player-webui")"
FIRMWARE_DIRTY="$(repo_dirty "$REPO_ROOT")"
NATIVE_DIRTY="$(repo_dirty "$REPO_ROOT/sources/proaudio-player-native")"
WEBUI_DIRTY="$(repo_dirty "$REPO_ROOT/sources/proaudio-player-webui")"

BUILD_STATE=clean
if [ "$FIRMWARE_DIRTY" = 1 ] || [ "$NATIVE_DIRTY" = 1 ] || [ "$WEBUI_DIRTY" = 1 ]; then
	BUILD_STATE=dirty
fi

BUILD_ID="${PROAUDIO_FIRMWARE_VERSION}-${PROAUDIO_FIRMWARE_CHANNEL}.fw${FIRMWARE_SHA}.native${NATIVE_SHA}.webui${WEBUI_SHA}.${BUILD_STATE}"

cat <<EOF
PROAUDIO_VERSION=$PROAUDIO_FIRMWARE_VERSION
PROAUDIO_CHANNEL=$PROAUDIO_FIRMWARE_CHANNEL
PROAUDIO_STATUS=$PROAUDIO_FIRMWARE_STATUS
PROAUDIO_BUILD_ID=$BUILD_ID
PROAUDIO_BUILD_STATE=$BUILD_STATE
PROAUDIO_FIRMWARE_SHA=$FIRMWARE_SHA
PROAUDIO_NATIVE_SHA=$NATIVE_SHA
PROAUDIO_WEBUI_SHA=$WEBUI_SHA
PROAUDIO_FIRMWARE_DIRTY=$FIRMWARE_DIRTY
PROAUDIO_NATIVE_DIRTY=$NATIVE_DIRTY
PROAUDIO_WEBUI_DIRTY=$WEBUI_DIRTY
EOF
