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


def test_native_audio_runtime_packages_unity_graph_and_generic_configs():
    native_makefile = (NATIVE_PACKAGE / "proaudio-player-native.mk").read_text(
        encoding="utf-8"
    )
    native_config = (NATIVE_PACKAGE / "Config.in").read_text(encoding="utf-8")

    assert "release/proaudio-player-limiter" not in native_makefile
    assert "scripts/proaudio-player-limiter-start" not in native_makefile
    assert "rm -f $(TARGET_DIR)/usr/bin/proaudio-player-limiter" in native_makefile
    assert "rm -f $(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-limiter.service" in native_makefile
    assert "rm -f $(TARGET_DIR)/usr/lib/systemd/system/proaudio-player-limiter.path" in native_makefile
    assert "scripts/proaudio-player-output-watch" in native_makefile
    assert "proaudio-player-output-watch.service" in native_makefile
    assert "config/audio.env.example" in native_makefile
    assert "scripts/audio-buses.sh" in native_makefile
    assert "config/wireplumber/51-proaudio-soft-mixer.conf" in native_makefile

    # Native source selection is runtime/Kconfig policy. Cargo.toml intentionally
    # has no feature matrix, so Buildroot must not manufacture stale Rust features.
    assert "PROAUDIO_PLAYER_NATIVE_FEATURES" not in native_makefile
    assert "PROAUDIO_PLAYER_NATIVE_CARGO_BUILD_OPTS" not in native_makefile
    assert "--no-default-features" not in native_makefile

    # DLNA is provided by gmrender-resurrect. Do not duplicate old GUPnP runtime
    # dependencies in _DEPENDENCIES: Buildroot requires those to be selected by
    # Kconfig, and the current renderer uses gmrender/libupnp instead.
    assert "select BR2_PACKAGE_GMRENDER_RESURRECT" in native_config
    assert "gupnp-av" not in native_makefile
    assert "gupnp-dlna" not in native_makefile

    # A generic package must never pull runtime configuration from a board profile.
    assert "board/raspberrypi4-64" not in native_makefile
    assert "$(@D)/config/spotifyd.conf" in native_makefile

    output_watch_service = (
        PLAYER_PACKAGE / "proaudio-player-output-watch.service"
    ).read_text(encoding="utf-8")
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
    assert 'load_loopback_into music_loop "$MUSIC_SINK" "$MASTER_SINK"' in buses
    assert 'load_loopback_into alert_loop "$ALERT_SINK" "$MASTER_SINK"' in buses
    assert 'load_loopback_into output_loop "$MASTER_SINK" "$output_target"' in buses
    assert 'PARKING_SINK="${PARKING_SINK:-proaudio_player_parking}"' in buses
    assert 'GRAPH_UNITY_DB="0.0"' in buses
    assert "proaudio-player-final-output" in buses

    # Generic AUTO selection must not privilege a hardware bus such as USB.
    assert "alsa_output\\.usb" not in buses
    assert "MASTER_SINK=proaudio_player_master" in audio_env
    assert "PARKING_SINK=proaudio_player_parking" in audio_env
    assert "OUTPUT_HEADROOM_DB" not in audio_env
    assert "LIMITER_" not in audio_env


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


def test_native_and_webui_share_authoritative_realtime_audio_contract():
    backend = (
        ROOT / "sources/proaudio-player-native/src/api/backend.rs"
    ).read_text(encoding="utf-8")
    webui_types = (
        ROOT / "sources/proaudio-player-webui/src/api/types.ts"
    ).read_text(encoding="utf-8")
    mixer = (
        ROOT / "sources/proaudio-player-webui/src/features/mixer/MixerPanel.tsx"
    ).read_text(encoding="utf-8")

    # Realtime status is software-only: MASTER is authoritative over SSE, while
    # expensive ALSA probing is reserved for explicit diagnostics endpoints.
    assert '"master": master' in backend
    assert '"hardware": Value::Null' in backend
    assert "primary_hardware_mixer" not in backend
    assert '"audio_hardware_read_only"' in backend
    assert '"audio_settings"' in backend
    assert '"meters"' in backend

    # The browser contract must describe the same fields and prefer SSE state for
    # MASTER/ALERT instead of polling the mixer to reconstruct realtime state.
    assert "master: AudioLevel | null;" in webui_types
    assert "capabilities: AudioOutputCapabilities;" in webui_types
    assert "props.status?.audio_levels.master" in mixer
    assert "lastStatusSignature" not in mixer


def test_persistent_state_and_spotify_receiver_are_runtime_safe():
    storage = (
        ROOT
        / "br2-external/board/raspberrypi4-64/rootfs-overlay/usr/libexec/"
        "proaudio-player/prepare-storage"
    ).read_text(encoding="utf-8")
    tmpfiles = (PLAYER_PACKAGE / "proaudio-player.tmpfiles.conf").read_text(encoding="utf-8")
    spotify_service = (PLAYER_PACKAGE / "proaudio-player-spotifyd.service").read_text(
        encoding="utf-8"
    )
    spotify_config = (
        ROOT / "sources/proaudio-player-native/config/spotifyd.conf"
    ).read_text(encoding="utf-8")
    mixer = (
        ROOT / "sources/proaudio-player-webui/src/features/mixer/MixerPanel.tsx"
    ).read_text(encoding="utf-8")

    for name in (
        "state.json",
        "provider-settings.yaml",
        "audio-settings.yaml",
        "audio-output.env",
    ):
        assert name in storage
    assert 'chmod 0600 "$data_mount/player-alert/$file"' in storage
    assert "/data/" not in tmpfiles

    # Spotify is a transport, not another user gain stage. Keep its discovery
    # credentials volatile because the arbiter deliberately restarts receivers.
    assert 'volume_controller = "none"' in spotify_config
    assert 'cache_path = "/run/proaudio-player/spotifyd"' in spotify_config
    assert "no_audio_cache = true" in spotify_config
    assert "ExecStartPre=/bin/rm -rf /run/proaudio-player/spotifyd" in spotify_service
    assert "ExecStartPre=/bin/mkdir -p /run/proaudio-player/spotifyd" in spotify_service

    # Losing /status must never fabricate a MUSIC level. /audio/mixer remains the
    # authoritative fallback; controls stay disabled until one source responds.
    assert "return mixerState()?.music;" in mixer
    assert "level('music') === undefined" in mixer
    assert "if (muted !== undefined)" in mixer


def test_dlna_worker_uses_a_private_non_loopback_interface():
    renderer = (PLAYER_PACKAGE / "dlna-renderer.sh").read_text(encoding="utf-8")
    service = (PLAYER_PACKAGE / "proaudio-player-dlna.service").read_text(
        encoding="utf-8"
    )
    native_config = (NATIVE_PACKAGE / "Config.in").read_text(encoding="utf-8")
    legacy_config = (PLAYER_PACKAGE / "Config.in").read_text(encoding="utf-8")
    kernel_fragment = (
        ROOT / "br2-external/board/raspberrypi4-64/linux-headless-usb.fragment"
    ).read_text(encoding="utf-8")
    native_dlna = (
        ROOT / "sources/proaudio-player-native/src/dlna.rs"
    ).read_text(encoding="utf-8")

    assert '--interface-name=lo' not in renderer
    assert 'interface="${DLNA_INTERFACE:-proaudio-dlna}"' in renderer
    assert '--interface-name="$interface"' in renderer
    assert "Environment=DLNA_INTERFACE=proaudio-dlna" in service
    assert "/sbin/ip link add proaudio-dlna type dummy" in service
    assert "/sbin/ip addr replace 169.254.253.1/32 dev proaudio-dlna" in service
    assert "select BR2_PACKAGE_IPROUTE2" in native_config
    assert "select BR2_PACKAGE_IPROUTE2" in legacy_config
    assert "CONFIG_DUMMY=y" in kernel_fragment
    assert "http://169.254.253.1:49494/upnp/control/rendertransport1" in native_dlna
