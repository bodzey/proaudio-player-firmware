import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"


def test_main_has_production_release_identity():
    release = (ROOT / "release.conf").read_text(encoding="utf-8")
    assert re.search(r"^PROAUDIO_FIRMWARE_VERSION=\d+\.\d+\.\d+$", release, re.M)
    assert "PROAUDIO_FIRMWARE_CHANNEL=production" in release
    assert "PROAUDIO_FIRMWARE_STATUS=stable" in release

    helper = (ROOT / "scripts/release-info.sh").read_text(encoding="utf-8")
    for key in (
        "PROAUDIO_BUILD_ID",
        "PROAUDIO_FIRMWARE_SHA",
        "PROAUDIO_NATIVE_SHA",
        "PROAUDIO_WEBUI_SHA",
    ):
        assert key in helper


def test_main_embeds_release_without_changing_pulse_audio_policy():
    post_build = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")
    assert 'RELEASE_FILE="$TARGET_DIR/etc/proaudio-release"' in post_build
    assert 'scripts/release-info.sh" "$REPO_ROOT" > "$RELEASE_FILE"' in post_build
    assert '"$TARGET_DIR/etc/issue"' in post_build

    # main intentionally remains the stable Pulse compatibility baseline.
    assert "pipewire-pulse" in post_build
    assert "libpulse client compatibility" in post_build
    assert "Pure-PipeWire" not in post_build


def test_main_produces_versioned_image_and_sdcard_alias():
    post_image = (BOARD / "post-image.sh").read_text(encoding="utf-8")
    assert "proaudio-player-rpi4-${PROAUDIO_VERSION}" in post_image
    assert 'ln -s "${ARTIFACT_NAME}" "${BINARIES_DIR}/sdcard.img"' in post_image
    assert "proaudio-image-name" in post_image
