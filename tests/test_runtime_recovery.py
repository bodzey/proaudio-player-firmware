from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLAYER_PACKAGE = ROOT / "br2-external/package/proaudio-player"
SPOTIFY_PACKAGE = ROOT / "br2-external/package/proaudio-spotifyd"
PI_SPOTIFY_OVERLAY = (
    ROOT
    / "br2-external/board/raspberrypi4-64/rootfs-overlay/etc/proaudio-player-alert/spotifyd.conf"
)


def test_persistent_runtime_files_are_reowned_for_native_daemon():
    tmpfiles = (PLAYER_PACKAGE / "proaudio-player.tmpfiles.conf").read_text(encoding="utf-8")
    for path in [
        "/data/player-alert/state.json",
        "/data/player-alert/provider-settings.yaml",
        "/data/player-alert/audio-settings.yaml",
        "/data/player-alert/audio-output.env",
    ]:
        assert f"z {path} 0600 proaudio-player proaudio-player -" in tmpfiles


def test_spotify_uses_single_generic_unity_gain_config():
    spotify_config = (
        ROOT / "sources/proaudio-player-native/config/spotifyd.conf"
    ).read_text(encoding="utf-8")
    service = (PLAYER_PACKAGE / "proaudio-player-spotifyd.service").read_text(encoding="utf-8")

    assert not PI_SPOTIFY_OVERLAY.exists()
    assert 'volume_controller = "none"' in spotify_config
    assert 'cache_path = "/run/proaudio-player/spotifyd"' in spotify_config
    assert "no_audio_cache = true" in spotify_config
    assert "ExecStartPre=/bin/rm -rf /run/proaudio-player/spotifyd" in service
    assert "ExecStartPre=/bin/mkdir -p /run/proaudio-player/spotifyd" in service


def test_spotify_discovery_malformed_blob_forces_clean_receiver_restart():
    patch = (
        SPOTIFY_PACKAGE
        / "0001-librespot-discovery-restart-on-short-credential-blob.patch"
    ).read_text(encoding="utf-8")

    assert "DiscoveryEvent::ServerError" in patch
    assert "Spotify discovery stream terminated" in patch
    assert "encrypted_blob_len < 36" in patch

