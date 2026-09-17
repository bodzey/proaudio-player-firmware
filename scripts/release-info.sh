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

short_sha()
{
	git -C "$1" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown\n'
}

PROAUDIO_FIRMWARE_VERSION="$(config_value PROAUDIO_FIRMWARE_VERSION)"
PROAUDIO_FIRMWARE_CHANNEL="$(config_value PROAUDIO_FIRMWARE_CHANNEL)"
PROAUDIO_FIRMWARE_STATUS="$(config_value PROAUDIO_FIRMWARE_STATUS)"
FIRMWARE_SHA="$(short_sha "$REPO_ROOT")"
NATIVE_SHA="$(short_sha "$REPO_ROOT/sources/proaudio-player-native")"
WEBUI_SHA="$(short_sha "$REPO_ROOT/sources/proaudio-player-webui")"
BUILD_ID="${PROAUDIO_FIRMWARE_VERSION}-${PROAUDIO_FIRMWARE_CHANNEL}-${PROAUDIO_FIRMWARE_STATUS}.fw${FIRMWARE_SHA}.native${NATIVE_SHA}.webui${WEBUI_SHA}"

cat <<EOF
PROAUDIO_VERSION=$PROAUDIO_FIRMWARE_VERSION
PROAUDIO_CHANNEL=$PROAUDIO_FIRMWARE_CHANNEL
PROAUDIO_STATUS=$PROAUDIO_FIRMWARE_STATUS
PROAUDIO_BUILD_ID=$BUILD_ID
PROAUDIO_FIRMWARE_SHA=$FIRMWARE_SHA
PROAUDIO_NATIVE_SHA=$NATIVE_SHA
PROAUDIO_WEBUI_SHA=$WEBUI_SHA
EOF
