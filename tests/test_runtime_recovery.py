from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLAYER_PACKAGE = ROOT / "br2-external/package/proaudio-player"
SPOTIFY_PACKAGE = ROOT / "br2-external/package/proaudio-spotifyd"


def test_persistent_runtime_files_are_reowned_for_native_daemon():
    storage = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/usr/libexec/"
        "proaudio-player/prepare-storage"
    ).read_text(encoding="utf-8")
    tmpfiles = (PLAYER_PACKAGE / "proaudio-player.tmpfiles.conf").read_text(encoding="utf-8")

    for name in (
        "state.json",
        "provider-settings.yaml",
        "audio-settings.yaml",
        "audio-output.env",
    ):
        assert name in storage
    assert 'chown proaudio-player:proaudio-player "$data_mount/player-alert/$file"' in storage
    assert 'chmod 0600 "$data_mount/player-alert/$file"' in storage
    assert "/data/" not in tmpfiles


def test_bind_mounts_avoid_local_fs_ordering_cycles():
    systemd = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/usr/lib/systemd/system"
    )
    for unit in (
        "srv-music.mount",
        "var-lib-proaudio\\x2dplayer.mount",
        "var-lib-proaudio\\x2dplayer\\x2dalert.mount",
    ):
        mount = (systemd / unit).read_text(encoding="utf-8")
        assert "DefaultDependencies=no" in mount
        assert "Requires=proaudio-storage.service" in mount
        assert "After=proaudio-storage.service" in mount
        assert "Conflicts=umount.target" in mount
        assert "Before=proaudio-storage-layout.target umount.target" in mount


def test_spotify_discovery_malformed_blob_forces_clean_receiver_restart():
    patch = (
        SPOTIFY_PACKAGE
        / "0001-librespot-discovery-restart-on-short-credential-blob.patch"
    ).read_text(encoding="utf-8")

    assert "DiscoveryEvent::ServerError" in patch
    assert "Spotify discovery stream terminated" in patch
    assert "encrypted_blob_len < 36" in patch


def test_rpi4_runtime_uses_hardware_watchdog_and_volatile_journal():
    overlay = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/etc/systemd"
    )
    watchdog = (overlay / "system.conf.d/20-proaudio-watchdog.conf").read_text(
        encoding="utf-8"
    )
    journal = (overlay / "journald.conf.d/20-proaudio-volatile.conf").read_text(
        encoding="utf-8"
    )

    assert "RuntimeWatchdogSec=10s" in watchdog
    assert "Storage=volatile" in journal
    assert "RuntimeMaxUse=16M" in journal
    assert "RuntimeMaxFileSize=4M" in journal
