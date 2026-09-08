from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "br2-external/package/proaudio-player"
SPOTIFY_PACKAGE = ROOT / "br2-external/package/proaudio-spotifyd"


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

    spotify_hash = (SPOTIFY_PACKAGE / "proaudio-spotifyd.hash").read_text(
        encoding="utf-8"
    )
    assert "spotifyd-0.4.2.crate" in spotify_hash
    assert "93f11b13d33be743aa23422db1c990d9de5997123fc8323eddc37cb3d5eb4f26" in spotify_hash
    assert "LICENSE" in spotify_hash


def test_rpi4_target_satisfies_player_contract_and_uses_real_interface():
    defconfig = (
        ROOT / "br2-external/configs/proaudio_rpi4_64_defconfig"
    ).read_text(encoding="utf-8")
    assert "BR2_TOOLCHAIN_EXTERNAL_BOOTLIN_AARCH64_GLIBC_BLEEDING_EDGE=y" in defconfig
    assert "BR2_TOOLCHAIN_EXTERNAL_BOOTLIN_AARCH64_GLIBC_STABLE=y" not in defconfig
    assert 'BR2_SYSTEM_DHCP="end0"' in defconfig
    assert "BR2_PACKAGE_PROAUDIO_PLAYER=y" in defconfig


def test_spotifyd_uses_verified_buildroot_cargo_source():
    makefile = (SPOTIFY_PACKAGE / "proaudio-spotifyd.mk").read_text(
        encoding="utf-8"
    )
    assert "spotifyd-$(PROAUDIO_SPOTIFYD_VERSION).crate" in makefile
    assert "https://static.crates.io/crates/spotifyd" in makefile
    assert "PROAUDIO_SPOTIFYD_DL_SUBDIR = spotifyd" in makefile
    assert "$(eval $(cargo-package))" in makefile
    assert "--no-default-features --features pulseaudio_backend" in makefile
    assert "PROAUDIO_SPOTIFYD_EXTRACT_CMDS" in makefile


def test_audio_bus_service_retries_if_hardware_is_late():
    service = (PACKAGE / "proaudio-player-buses.service").read_text(encoding="utf-8")
    assert "Type=oneshot" in service
    assert "Restart=on-failure" in service
    assert "RestartSec=5" in service
