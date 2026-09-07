from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "br2-external/package/proaudio-player"


def test_core_submodule_uses_protocol_relative_repository_url():
    modules = (ROOT / ".gitmodules").read_text(encoding="utf-8")
    assert "path = sources/proaudio-player" in modules
    assert "url = ../proaudio_player.git" in modules


def test_firmware_installs_core_media_and_wireplumber_rule():
    makefile = (PACKAGE / "proaudio-player.mk").read_text(encoding="utf-8")
    for name in ("alarm_start.mp3", "alarm_end.mp3", "minute_silence.mp3"):
        assert f"default_media/{name}" in makefile
        assert f"media/{name}" in makefile
    assert "config/wireplumber/51-proaudio-soft-mixer.conf" in makefile

    embedded_profile = (
        ROOT
        / "br2-external/board/common/rootfs-overlay/etc/wireplumber/"
        "wireplumber.conf.d/90-proaudio.conf"
    ).read_text(encoding="utf-8")
    assert "main-embedded" in embedded_profile
    assert "api.alsa.soft-mixer" not in embedded_profile


def test_required_time_sync_and_source_hash_enforcement_are_enabled():
    config = (PACKAGE / "Config.in").read_text(encoding="utf-8")
    assert "select BR2_PACKAGE_SYSTEMD_TIMESYNCD" in config

    for name in ("proaudio_rpi4_64_defconfig", "proaudio_qemu_aarch64_defconfig"):
        defconfig = (
            ROOT / "br2-external/configs" / name
        ).read_text(encoding="utf-8")
        assert "BR2_DOWNLOAD_FORCE_CHECK_HASHES=y" in defconfig

    spotify_hash = (
        ROOT
        / "br2-external/package/proaudio-spotifyd/proaudio-spotifyd.hash"
    ).read_text(encoding="utf-8")
    assert "spotifyd-0.4.2.tar.gz" in spotify_hash
    assert "LICENSE" in spotify_hash


def test_audio_bus_service_retries_if_hardware_is_late():
    service = (PACKAGE / "proaudio-player-buses.service").read_text(encoding="utf-8")
    assert "Type=oneshot" in service
    assert "Restart=on-failure" in service
    assert "RestartSec=5" in service
