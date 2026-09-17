import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"


def test_dev_release_identity_is_explicit_and_semantic():
    release = (ROOT / "release.conf").read_text(encoding="utf-8")
    assert re.search(r"^PROAUDIO_FIRMWARE_VERSION=\d+\.\d+\.\d+$", release, re.M)
    assert "PROAUDIO_FIRMWARE_CHANNEL=dev" in release
    assert "PROAUDIO_FIRMWARE_STATUS=development" in release


def test_release_helper_tracks_all_source_revisions_and_cleanliness():
    helper = (ROOT / "scripts/release-info.sh").read_text(encoding="utf-8")
    for key in (
        "PROAUDIO_BUILD_ID",
        "PROAUDIO_BUILD_STATE",
        "PROAUDIO_FIRMWARE_SHA",
        "PROAUDIO_NATIVE_SHA",
        "PROAUDIO_WEBUI_SHA",
        "PROAUDIO_FIRMWARE_DIRTY",
        "PROAUDIO_NATIVE_DIRTY",
        "PROAUDIO_WEBUI_DIRTY",
    ):
        assert key in helper
    assert "--untracked-files=normal" in helper
    assert "--ignore-submodules=all" in helper


def test_native_image_embeds_release_identity_and_version_command():
    post_build = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")
    assert 'RELEASE_FILE="$TARGET_DIR/etc/proaudio-release"' in post_build
    assert 'scripts/release-info.sh" "$REPO_ROOT" > "$RELEASE_FILE"' in post_build
    assert '"$TARGET_DIR/usr/bin/proaudio-version"' in post_build
    assert '"$TARGET_DIR/etc/issue"' in post_build

    # Versioning must not alter the known-good Pulse compatibility baseline.
    assert "PipeWire-Pulse is the only PulseAudio-compatible server" in post_build
    assert "libpulse" in post_build
    assert "pactl" in post_build


def test_image_has_versioned_artifact_stable_alias_and_checksum():
    post_image = (BOARD / "post-image.sh").read_text(encoding="utf-8")
    assert "proaudio-player-rpi4-${PROAUDIO_VERSION}-${PROAUDIO_CHANNEL}" in post_image
    assert 'ln -s "${ARTIFACT_NAME}" "${BINARIES_DIR}/sdcard.img"' in post_image
    assert "proaudio-image-name" in post_image
    assert 'sha256sum "${ARTIFACT_NAME}"' in post_image
