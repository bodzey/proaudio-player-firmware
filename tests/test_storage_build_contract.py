from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"
PLAYER_PACKAGE = ROOT / "br2-external/package/proaudio-player"
WEBUI_PACKAGE = ROOT / "br2-external/package/proaudio-webui"


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


def test_webui_reuses_verified_npm_cache():
    makefile = (WEBUI_PACKAGE / "proaudio-webui.mk").read_text(
        encoding="utf-8"
    )

    assert 'npm_config_cache="$(DL_DIR)/br-npm-cache"' in makefile
    assert "npm_config_prefer_offline=true" in makefile
    assert "npm ci --include=dev" in makefile
