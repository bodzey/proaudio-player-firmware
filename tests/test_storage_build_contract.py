from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"
PLAYER_PACKAGE = ROOT / "br2-external/package/proaudio-player"
NATIVE_PACKAGE = ROOT / "br2-external/package/proaudio-player-native"
WEBUI_PACKAGE = ROOT / "br2-external/package/proaudio-webui"
SYSTEMD_OVERLAY = BOARD / "rootfs-overlay/etc/systemd/system"


def test_persistent_storage_boot_work_is_bounded_and_migration_safe():
    storage = (
        BOARD
        / "rootfs-overlay/usr/libexec/proaudio-player/prepare-storage"
    ).read_text(encoding="utf-8")

    assert "ensure_data_layout" in storage
    assert "chown -R" not in storage
    assert "storage_ready=0" in storage
    assert '[ -e "$done_marker" ] && storage_ready=1' in storage
    assert (
        'if [ "$storage_ready" -eq 0 ] || [ -e "$pending_marker" ]; then'
        in storage
    )
    assert "printf ',+\\n'" in storage
    assert 'sfdisk --no-reread -N "$data_partition_number" "$disk"' in storage
    assert "partition_table_size" in storage
    assert "stale partition expansion marker detected" in storage
    assert "partition table update did not enlarge DATA" in storage
    assert 'resize2fs "$data_partition"' in storage


def test_storage_dependent_path_units_do_not_join_early_paths_target():
    for name in (
        "proaudio-player-audio-output.path.d/storage.conf",
        "proaudio-player-output-apply.path.d/storage.conf",
    ):
        dropin = (SYSTEMD_OVERLAY / name).read_text(encoding="utf-8")
        assert "DefaultDependencies=no" in dropin
        assert "Requires=proaudio-storage-layout.target" in dropin
        assert "After=proaudio-storage-layout.target" in dropin
        assert "Conflicts=shutdown.target" in dropin
        assert "Before=shutdown.target" in dropin


def test_networkd_wait_online_cannot_block_offline_boot():
    override = (
        SYSTEMD_OVERLAY
        / "systemd-networkd-wait-online.service.d/proaudio.conf"
    ).read_text(encoding="utf-8")

    assert "ExecStart=" in override
    assert "ExecStart=/bin/true" in override


def test_shared_runtime_directory_is_explicit_and_private():
    tmpfiles = (PLAYER_PACKAGE / "proaudio-player.tmpfiles.conf").read_text(
        encoding="utf-8"
    )

    assert (
        "d /run/proaudio-player 0700 proaudio-player proaudio-player -"
        in tmpfiles
    )


def test_data_filesystem_uses_all_capacity():
    post_image = (BOARD / "post-image.sh").read_text(encoding="utf-8")

    assert "\t-m 0 \\" in post_image
    assert "\t-m 1 \\" not in post_image


def test_alert_token_is_not_baked_into_board_overlay():
    overlay_token = (
        BOARD / "rootfs-overlay/etc/proaudio-player-alert/alerts-token"
    )
    native_makefile = (
        NATIVE_PACKAGE / "proaudio-player-native.mk"
    ).read_text(encoding="utf-8")
    legacy_makefile = (PLAYER_PACKAGE / "proaudio-player.mk").read_text(
        encoding="utf-8"
    )

    assert not overlay_token.exists()
    for makefile in (native_makefile, legacy_makefile):
        assert "$(INSTALL) -D -m 0600 /dev/null" in makefile
        assert "$(TARGET_DIR)/etc/proaudio-player-alert/alerts-token" in makefile


def test_webui_reuses_verified_npm_cache():
    makefile = (WEBUI_PACKAGE / "proaudio-webui.mk").read_text(
        encoding="utf-8"
    )

    assert 'npm_config_cache="$(DL_DIR)/br-npm-cache"' in makefile
    assert "npm_config_prefer_offline=true" in makefile
    assert "npm ci --include=dev" in makefile
