from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NATIVE_PACKAGE = ROOT / "br2-external/package/proaudio-player-native"
RUNTIME_PACKAGE = NATIVE_PACKAGE / "runtime"
SPOTIFY_PACKAGE = ROOT / "br2-external/package/proaudio-spotifyd"
NETWORK_PACKAGE = ROOT / "br2-external/package/proaudio-networkd"
COMMON_OVERLAY = ROOT / "br2-external/board/common/rootfs-overlay"


def test_native_submodule_uses_protocol_relative_repository_url():
    modules = (ROOT / ".gitmodules").read_text(encoding="utf-8")
    assert "path = sources/proaudio-player-native" in modules
    assert "url = ../proaudio-player-native.git" in modules


def test_firmware_installs_core_media_and_wireplumber_rule():
    makefile = (NATIVE_PACKAGE / "proaudio-player-native.mk").read_text(
        encoding="utf-8"
    )
    for name in ("alarm_start.mp3", "alarm_end.mp3", "minute_silence.mp3"):
        assert f"assets/announcements/{name}" in makefile
    assert "config/wireplumber/51-proaudio-soft-mixer.conf" in makefile

    embedded_profile = (
        ROOT
        / "br2-external/board/common/rootfs-overlay/etc/wireplumber/"
        "wireplumber.conf.d/90-proaudio.conf"
    ).read_text(encoding="utf-8")
    assert "main-embedded" in embedded_profile
    assert "api.alsa.soft-mixer" not in embedded_profile


def test_required_time_sync_and_source_hash_enforcement_are_enabled():
    config = (NATIVE_PACKAGE / "Config.in").read_text(encoding="utf-8")
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
    assert "BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE=y" in defconfig
    assert "BR2_PACKAGE_PROAUDIO_WEBUI=y" in defconfig
    assert "BR2_PACKAGE_PROAUDIO_NETWORKD=y" in defconfig
    assert "BR2_PACKAGE_PROAUDIO_PLAYER=y" not in defconfig
    assert "BR2_PACKAGE_PYTHON3" not in defconfig


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
    service = (RUNTIME_PACKAGE / "proaudio-player-buses.service").read_text(encoding="utf-8")
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
    resolved = (
        COMMON_OVERLAY / "etc/systemd/resolved.conf.d/10-proaudio.conf"
    ).read_text(encoding="utf-8")
    makefile = (NETWORK_PACKAGE / "proaudio-networkd.mk").read_text(
        encoding="utf-8"
    )
    assert "[Resolve]\nMulticastDNS=no\nLLMNR=no" in resolved
    assert "10-proaudio-resolved.conf" not in makefile


def test_wifi_regdomain_and_ap_transition_are_integrated_in_rust():
    cmdline = (
        ROOT / "br2-external/board/raspberrypi4-64/cmdline.txt"
    ).read_text(encoding="utf-8")
    network = (
        NETWORK_PACKAGE / "rust/src/network.rs"
    ).read_text(encoding="utf-8")

    assert "cfg80211.ieee80211_regdom=UA" in cmdline
    assert '"--rescan",' in network
    assert '"auto",' in network
    assert '"device",' in network
    assert '"wifi",' in network
    assert '"rescan",' in network
    assert '"ssid",' in network
    assert 'args.extend_from_slice(&["hidden", "yes"])' in network
    assert "prepare_station_connection" in network


def test_mpd_first_boot_state_exists_but_database_is_not_seeded():
    storage = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/usr/libexec/"
        "proaudio-player/prepare-storage"
    ).read_text(encoding="utf-8")
    assert "database_file=$data_mount/player-alert/mpd/database" in storage
    assert '[ ! -s "$database_file" ]' in storage
    assert 'rm -f "$database_file"' in storage
    assert "for file in database state; do" not in storage
    assert "state_file=$data_mount/player-alert/mpd/state" in storage
    assert ': > "$state_file"' in storage
    assert 'chmod 0640 "$state_file"' in storage


def test_captive_portal_advertises_rfc8910_url_and_redirects_probes():
    network = (
        NETWORK_PACKAGE / "rust/src/network.rs"
    ).read_text(encoding="utf-8")
    portal = (
        NETWORK_PACKAGE / "rust/src/portal.rs"
    ).read_text(encoding="utf-8")

    assert 'format!("114,http://{}/", self.config.setup_address)' in network
    assert "raw_path.split('?')" in portal
    assert 'format!("http://{}/", config.setup_address)' in portal


def test_storage_layout_is_device_agnostic_and_ordered():
    board = ROOT / "br2-external/board/raspberrypi4-64"
    overlay = board / "rootfs-overlay"
    systemd = overlay / "usr/lib/systemd/system"
    script = (
        overlay / "usr/libexec/proaudio-player/prepare-storage"
    ).read_text(encoding="utf-8")
    service = (systemd / "proaudio-storage.service").read_text(encoding="utf-8")
    data_mount = (systemd / "data.mount").read_text(encoding="utf-8")
    layout = (systemd / "proaudio-storage-layout.target").read_text(encoding="utf-8")
    music_mount = (systemd / "srv-music.mount").read_text(encoding="utf-8")
    player_mount = (systemd / "var-lib-proaudio\\x2dplayer.mount").read_text(
        encoding="utf-8"
    )
    alert_mount = (
        systemd / "var-lib-proaudio\\x2dplayer\\x2dalert.mount"
    ).read_text(encoding="utf-8")
    genimage = (board / "genimage.cfg.in").read_text(encoding="utf-8")
    cmdline = (board / "cmdline.txt").read_text(encoding="utf-8")
    post_build = (board / "post-build.sh").read_text(encoding="utf-8")
    tmpfiles = (RUNTIME_PACKAGE / "proaudio-player.tmpfiles.conf").read_text(encoding="utf-8")

    assert "root=PARTUUID=50524155-02" in cmdline
    assert "root=/dev/mmcblk" not in cmdline
    assert "disk-signature = 0x50524155" in genimage
    assert "partition data" in genimage
    assert 'image = "data.ext4"' in genimage

    assert 'findmnt -n -o SOURCE,FSTYPE "$data_mount"' in script
    assert "SYSTEM and DATA are not on the same boot disk" in script
    assert "DATA is not the final partition" in script
    assert 'resize2fs "$data_partition"' in script
    assert "/dev/mmcblk0" not in script
    assert "Requires=data.mount" in service
    assert "After=data.mount" in service
    assert "systemd-tmpfiles-setup.service" not in service
    assert "TimeoutStartSec=0" in service
    assert "What=/dev/disk/by-partuuid/50524155-03" in data_mount
    assert "Options=noatime,nodev,nosuid,noexec" in data_mount

    assert "ln -s /data" not in post_build
    assert 'if [ -L "$path" ]' in post_build
    assert "/data/" not in tmpfiles

    assert "Requires=srv-music.mount" in layout
    assert "var-lib-proaudio\\x2dplayer.mount" in layout
    assert "var-lib-proaudio\\x2dplayer\\x2dalert.mount" in layout

    for mount, source, target, mode in (
        (music_mount, "/data/music", "/srv/music", "0755"),
        (player_mount, "/data/player", "/var/lib/proaudio-player", "0750"),
        (
            alert_mount,
            "/data/player-alert",
            "/var/lib/proaudio-player-alert",
            "0750",
        ),
    ):
        assert "Requires=proaudio-storage.service" in mount
        assert "After=proaudio-storage.service" in mount
        assert f"What={source}" in mount
        assert f"Where={target}" in mount
        assert "Options=bind" in mount
        assert f"DirectoryMode={mode}" in mount


def test_rpi_profiles_share_fixed_system_and_growable_data_contract():
    for name in ("proaudio_rpi4_64_defconfig", "proaudio_rpi4_64_native_defconfig"):
        defconfig = (ROOT / "br2-external/configs" / name).read_text(encoding="utf-8")
        assert 'BR2_TARGET_ROOTFS_EXT2_LABEL="PROAUDIO_SYSTEM"' in defconfig
        assert 'BR2_TARGET_ROOTFS_EXT2_SIZE="768M"' in defconfig
        assert "BR2_PACKAGE_E2FSPROGS_RESIZE2FS=y" in defconfig
        assert "BR2_PACKAGE_UTIL_LINUX_BINARIES=y" in defconfig
        assert (
            'BR2_ROOTFS_POST_IMAGE_SCRIPT="$(BR2_EXTERNAL_PROAUDIO_PATH)/'
            'board/raspberrypi4-64/post-image.sh"'
        ) in defconfig


def test_player_services_require_initialized_data_storage():
    systemd = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/etc/systemd/system"
    )
    for unit in (
        "proaudio-player-buses.service",
        "proaudio-player-native.service",
        "proaudio-player-mpd.service",
        "proaudio-player-spotifyd.service",
        "proaudio-player-shairport.service",
        "proaudio-player-dlna.service",
        "proaudio-player-audio-output.path",
    ):
        dropin = (systemd / f"{unit}.d/storage.conf").read_text(encoding="utf-8")
        assert "Requires=proaudio-storage-layout.target" in dropin
        assert "After=proaudio-storage-layout.target" in dropin

    native_dropin = (
        systemd / "proaudio-player-native.service.d/storage.conf"
    ).read_text(encoding="utf-8")
    assert "[Service]\nStateDirectory=\n" in native_dropin

    overlay = ROOT / "br2-external/board/raspberrypi4-64/rootfs-overlay"
    assert not (overlay / "usr/libexec/proaudio-player/grow-rootfs").exists()
    assert not (overlay / "usr/lib/systemd/system/proaudio-grow-rootfs.service").exists()


def test_alert_media_and_runtime_controls_use_persistent_storage():
    native = ROOT / "sources/proaudio-player-native"
    webui = ROOT / "sources/proaudio-player-webui"
    config = (native / "config/config.yaml.example").read_text(encoding="utf-8")
    backend = (native / "src/api/backend.rs").read_text(encoding="utf-8")
    alerts = (native / "src/alerts.rs").read_text(encoding="utf-8")
    types = (webui / "src/api/types.ts").read_text(encoding="utf-8")
    panel = (webui / "src/features/alerts/AlertsPanel.tsx").read_text(encoding="utf-8")
    storage = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/usr/libexec/"
        "proaudio-player/prepare-storage"
    ).read_text(encoding="utf-8")

    for name in ("alarm_start.mp3", "alarm_end.mp3", "minute_silence.mp3"):
        assert f'/var/lib/proaudio-player-alert/media/{name}' in config
        assert name in storage

    assert '"/settings/alerts/media"' in backend
    assert '"/settings/alerts/media/{kind}"' in backend
    assert "atomic_file::write" in backend
    assert "notifications_enabled" in alerts
    assert "export type AlertMediaKind" in types
    assert "minute_silence_enabled: boolean" in types
    assert "Файли сповіщень" in panel
    assert "Увімкнути систему сповіщень" in panel


def test_rpi4_post_image_refreshes_external_boot_policy_every_build():
    post_image = (
        ROOT / "br2-external/board/raspberrypi4-64/post-image.sh"
    ).read_text(encoding="utf-8")

    config_copy = (
        'install -D -m 0644 "${BOARD_DIR}/config.txt" '
        '"${BINARIES_DIR}/rpi-firmware/config.txt"'
    )
    cmdline_copy = (
        'install -D -m 0644 "${BOARD_DIR}/cmdline.txt" '
        '"${BINARIES_DIR}/rpi-firmware/cmdline.txt"'
    )

    assert config_copy in post_image
    assert cmdline_copy in post_image
    assert post_image.index(config_copy) < post_image.index("FILES=()")
    assert post_image.index(cmdline_copy) < post_image.index("FILES=()")


def test_firmware_contains_no_linkplay_or_4stream_markers():
    forbidden = ("linkplay", "4stream", "httpapi.asp", "_linkplay._tcp")
    for path in (ROOT / "br2-external").rglob("*"):
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8").lower()
        except UnicodeDecodeError:
            continue
        for marker in forbidden:
            assert marker not in content, f"{marker} leaked into {path.relative_to(ROOT)}"
