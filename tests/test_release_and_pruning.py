import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"
CONFIG = ROOT / "br2-external/configs/proaudio_rpi4_64_native_defconfig"
SPOTIFY_SERVICE = (
    ROOT / "br2-external/package/proaudio-player/proaudio-player-spotifyd.service"
)


def test_development_firmware_has_explicit_release_identity():
    release = (ROOT / "release.conf").read_text(encoding="utf-8")
    assert re.search(r"^PROAUDIO_FIRMWARE_VERSION=\d+\.\d+\.\d+$", release, re.M)
    assert "PROAUDIO_FIRMWARE_CHANNEL=development" in release
    assert "PROAUDIO_FIRMWARE_STATUS=testing" in release

    helper = (ROOT / "scripts/release-info.sh").read_text(encoding="utf-8")
    for key in (
        "PROAUDIO_BUILD_ID",
        "PROAUDIO_FIRMWARE_SHA",
        "PROAUDIO_NATIVE_SHA",
        "PROAUDIO_WEBUI_SHA",
    ):
        assert key in helper

    post_build = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")
    assert 'scripts/release-info.sh\" \"$REPO_ROOT\" > \"$TARGET_DIR/etc/proaudio-release\"' in post_build
    assert '\"$TARGET_DIR/etc/issue\"' in post_build

    post_image = (BOARD / "post-image.sh").read_text(encoding="utf-8")
    assert "proaudio-player-rpi4-${PROAUDIO_VERSION}" in post_image
    assert 'ln -s "${ARTIFACT_NAME}" "${BINARIES_DIR}/sdcard.img"' in post_image
    assert "proaudio-image-name" in post_image


def test_runtime_pruning_keeps_audio_stack_but_removes_unused_helpers():
    post_build = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")

    for artifact in (
        "avahi-dnsconfd",
        "libspa-audiotestsrc.so",
        "libspa-ffmpeg.so",
        "libspa-videoconvert.so",
        "libspa-videotestsrc.so",
        "libpipewire-module-raop-discover.so",
        "libpipewire-module-raop-sink.so",
        "NetworkManager-wait-online.service",
        "systemd-networkd-wait-online.service",
    ):
        assert artifact in post_build

    assert "pw-record" in post_build
    assert "libpulse" in post_build


def test_networking_has_single_explicit_ethernet_configuration():
    defconfig = CONFIG.read_text(encoding="utf-8")
    assert "BR2_PACKAGE_SYSTEMD_NETWORKD=y" in defconfig
    assert "BR2_SYSTEM_DHCP=" not in defconfig

    spotify = SPOTIFY_SERVICE.read_text(encoding="utf-8")
    assert "network-online.target" not in spotify
    assert "After=dbus.service network.target proaudio-player-buses.service" in spotify


def test_firmware_tracks_native_dev_after_pure_pipewire_merge():
    gitmodules = (ROOT / ".gitmodules").read_text(encoding="utf-8")
    native_section = gitmodules.split(
        '[submodule "sources/proaudio-player-native"]', 1
    )[1].split('[submodule "sources/proaudio-player-webui"]', 1)[0]
    assert "branch = dev" in native_section
