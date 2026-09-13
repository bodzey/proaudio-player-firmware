from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "br2-external/package/proaudio-player"
SPOTIFY_PACKAGE = ROOT / "br2-external/package/proaudio-spotifyd"
NETWORK_PACKAGE = ROOT / "br2-external/package/proaudio-networkd"


def test_native_submodule_uses_protocol_relative_repository_url():
    modules = (ROOT / ".gitmodules").read_text(encoding="utf-8")
    assert "path = sources/proaudio-player-native" in modules
    assert "url = ../proaudio-player-native.git" in modules


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


def test_unplugged_ethernet_does_not_degrade_boot():
    network = (NETWORK_PACKAGE / "10-proaudio-ethernet.network").read_text(
        encoding="utf-8"
    )
    assert "[Link]\nRequiredForOnline=no" in network
    assert "[Network]\nDHCP=ipv4" in network


def test_avahi_is_the_only_mdns_responder():
    resolved = (NETWORK_PACKAGE / "10-proaudio-resolved.conf").read_text(
        encoding="utf-8"
    )
    makefile = (NETWORK_PACKAGE / "proaudio-networkd.mk").read_text(
        encoding="utf-8"
    )
    assert "[Resolve]\nMulticastDNS=no\nLLMNR=no" in resolved
    assert "resolved.conf.d/10-proaudio.conf" in makefile


def test_wifi_regdomain_is_early_and_provisioning_avoids_duplicate_scan():
    cmdline = (
        ROOT / "br2-external/board/raspberrypi4-64/cmdline.txt"
    ).read_text(encoding="utf-8")
    daemon = (NETWORK_PACKAGE / "proaudio-networkd").read_text(encoding="utf-8")

    assert "cfg80211.ieee80211_regdom=UA" in cmdline
    assert '"device", "wifi", "rescan"' not in daemon
    assert '"--rescan", "auto"' in daemon


def test_mpd_first_boot_runtime_files_exist_before_service_start():
    tmpfiles = (
        ROOT / "br2-external/package/proaudio-player/proaudio-player.tmpfiles.conf"
    ).read_text(encoding="utf-8")
    for name in ("database", "state"):
        assert (
            f"f /var/lib/proaudio-player-alert/mpd/{name} "
            "0640 proaudio-player proaudio-player -"
        ) in tmpfiles


def test_captive_portal_advertises_rfc8910_url_and_redirects_probes():
    daemon = (NETWORK_PACKAGE / "proaudio-networkd").read_text(encoding="utf-8")
    assert 'f"--dhcp-option=114,http://{addr}/"' in daemon
    assert "urllib.parse.urlsplit(self.path).path" in daemon
    assert "self._redirect_setup()" in daemon


def test_first_boot_storage_growth_is_device_agnostic_and_ordered():
    script = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/usr/libexec/"
        "proaudio-player/grow-rootfs"
    ).read_text(encoding="utf-8")
    service = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/usr/lib/systemd/"
        "system/proaudio-grow-rootfs.service"
    ).read_text(encoding="utf-8")

    assert "findmnt -n -o SOURCE,FSTYPE /" in script
    assert "/sys/class/block/$partition_name/partition" in script
    assert 'disk=/dev/$disk_name' in script
    assert "/dev/mmcblk0" not in script
    assert 'case "$root_fstype" in' in script
    assert 'resize2fs "$root_partition"' in script
    assert "root partition is not last" in script
    assert "Before=multi-user.target" in service
    assert "ConditionPathExists=!/var/lib/proaudio-storage-grow/done" in service
    assert "TimeoutStartSec=0" in service
