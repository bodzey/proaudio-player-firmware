from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLAYER_PACKAGE = ROOT / "br2-external/package/proaudio-player"
SPOTIFY_PACKAGE = ROOT / "br2-external/package/proaudio-spotifyd"

def test_persistent_runtime_files_are_reowned_for_native_daemon():
    tmpfiles = (PLAYER_PACKAGE / "proaudio-player.tmpfiles.conf").read_text(encoding="utf-8")
    for path in [
        "/data/player-alert/state.json",
        "/data/player-alert/provider-settings.yaml",
        "/data/player-alert/audio-settings.yaml",
        "/data/player-alert/audio-output.env",
    ]:
        assert f"z {path} 0600 proaudio-player proaudio-player -" in tmpfiles


def test_spotify_discovery_malformed_blob_forces_clean_receiver_restart():
    patch = (
        SPOTIFY_PACKAGE
        / "0001-librespot-discovery-restart-on-short-credential-blob.patch"
    ).read_text(encoding="utf-8")

    assert "DiscoveryEvent::ServerError" in patch
    assert "Spotify discovery stream terminated" in patch
    assert "encrypted_blob_len < 36" in patch

