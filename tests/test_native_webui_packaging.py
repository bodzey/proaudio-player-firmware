from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NATIVE_PACKAGE = ROOT / "br2-external/package/proaudio-player-native"
PLAYER_PACKAGE = ROOT / "br2-external/package/proaudio-player"
WEBUI_PACKAGE = ROOT / "br2-external/package/proaudio-webui"
NATIVE_DEFCONFIG = ROOT / "br2-external/configs/proaudio_rpi4_64_native_defconfig"


def test_webui_is_an_explicit_optional_package_separate_from_native_player():
    external_config = (ROOT / "br2-external/Config.in").read_text(encoding="utf-8")
    native_makefile = (NATIVE_PACKAGE / "proaudio-player-native.mk").read_text(encoding="utf-8")
    webui_config = (WEBUI_PACKAGE / "Config.in").read_text(encoding="utf-8")
    webui_makefile = (WEBUI_PACKAGE / "proaudio-webui.mk").read_text(encoding="utf-8")
    native_defconfig = NATIVE_DEFCONFIG.read_text(encoding="utf-8")

    assert "package/proaudio-webui/Config.in" in external_config
    assert "BR2_PACKAGE_PROAUDIO_WEBUI" in webui_config
    assert "default y" not in webui_config
    assert (
        "PROAUDIO_WEBUI_SITE = $(BR2_EXTERNAL_PROAUDIO_PATH)/../sources/proaudio-player-webui"
        in webui_makefile
    )
    assert "PROAUDIO_WEBUI_SITE_METHOD = local" in webui_makefile
    assert "package-lock.json" in webui_makefile
    assert "npm ci --include=dev" in webui_makefile
    assert "/usr/share/proaudio-player/webui" in webui_makefile

    # This development image explicitly opts into the frontend.
    assert "BR2_PACKAGE_PROAUDIO_WEBUI=y" in native_defconfig

    # With the Kconfig symbol unset, Buildroot must not select/package Web UI.
    # The native control plane itself has no build dependency on frontend assets.
    assert "proaudio-webui" not in native_makefile.lower()
    assert "/webui" not in native_makefile.lower()


def test_native_audio_runtime_packages_final_limiter_and_generic_configs():
    native_makefile = (NATIVE_PACKAGE / "proaudio-player-native.mk").read_text(
        encoding="utf-8"
    )

    assert "release/proaudio-player-limiter" in native_makefile
    assert "/usr/bin/proaudio-player-limiter" in native_makefile
    assert "scripts/proaudio-player-limiter-start" in native_makefile
    assert "proaudio-player-limiter.service" in native_makefile
    assert "proaudio-player-limiter.path" in native_makefile
    assert "scripts/proaudio-player-output-watch" in native_makefile
    assert "proaudio-player-output-watch.service" in native_makefile
    assert "config/audio.env.example" in native_makefile
    assert "scripts/audio-buses.sh" in native_makefile
    assert "config/wireplumber/51-proaudio-soft-mixer.conf" in native_makefile

    # A generic package must never pull runtime configuration from a board profile.
    assert "board/raspberrypi4-64" not in native_makefile
    assert "$(@D)/config/spotifyd.conf" in native_makefile

    limiter_service = (PLAYER_PACKAGE / "proaudio-player-limiter.service").read_text(
        encoding="utf-8"
    )
    limiter_path = (PLAYER_PACKAGE / "proaudio-player-limiter.path").read_text(
        encoding="utf-8"
    )
    output_watch_service = (
        PLAYER_PACKAGE / "proaudio-player-output-watch.service"
    ).read_text(encoding="utf-8")
    assert "After=proaudio-player-buses.service" in limiter_service
    assert "Restart=on-failure" in limiter_service
    assert "proaudio-player-limiter-start" in limiter_service
    assert "/run/proaudio-player/proaudio-player-bus-modules" in limiter_path
    assert "proaudio-player-output-watch" in output_watch_service
    assert "Restart=always" in output_watch_service


def test_native_audio_topology_has_one_final_physical_output_path():
    buses = (
        ROOT / "sources/proaudio-player-native/scripts/audio-buses.sh"
    ).read_text(encoding="utf-8")
    audio_env = (
        ROOT / "sources/proaudio-player-native/config/audio.env.example"
    ).read_text(encoding="utf-8")

    assert "MASTER_SINK=\"${MASTER_SINK:-proaudio_player_master}\"" in buses
    assert 'music_loop="$(load_loopback "$MUSIC_SINK" "$MASTER_SINK")"' in buses
    assert 'alert_loop="$(load_loopback "$ALERT_SINK" "$MASTER_SINK")"' in buses
    assert 'load_loopback "$MUSIC_SINK" "$physical"' not in buses
    assert 'load_loopback "$ALERT_SINK" "$physical"' not in buses

    # Generic AUTO selection must not privilege a hardware bus such as USB.
    assert "alsa_output\\.usb" not in buses
    assert "MASTER_SINK=proaudio_player_master" in audio_env
    assert "LIMITER_ENABLED=true" in audio_env
    assert "LIMITER_CEILING_DB=-1.0" in audio_env


def test_native_audio_keeps_physical_gain_at_unity_and_never_unmutes_during_probe():
    buses = (
        ROOT / "sources/proaudio-player-native/scripts/audio-buses.sh"
    ).read_text(encoding="utf-8")
    audio_env = (
        ROOT / "sources/proaudio-player-native/config/audio.env.example"
    ).read_text(encoding="utf-8")

    assert 'OUTPUT_VOLUME_PERCENT="${OUTPUT_VOLUME_PERCENT:-100}"' in buses
    assert '[[ "$OUTPUT_VOLUME_PERCENT" != "100" ]]' in buses
    assert 'pactl set-sink-volume "$physical" 100%' in buses
    assert "OUTPUT_VOLUME_PERCENT=100" in audio_env

    # Multi-channel hardware controls are explicitly re-applied, but the ALSA
    # playback switch must remain untouched while the physical sink is muted.
    assert "reapply_playback_channels" in buses
    assert 'sset "$control" "$raw_values"' in buses
    assert 'sset "$control" "$raw_values" unmute' not in buses
