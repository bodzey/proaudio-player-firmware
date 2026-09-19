from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
QEMU_BOARD = ROOT / "br2-external/board/qemu-aarch64"


def test_qemu_profile_runs_current_native_and_webui_stack():
    config = (
        ROOT / "br2-external/configs/proaudio_qemu_aarch64_defconfig"
    ).read_text(encoding="utf-8")

    assert "BR2_PACKAGE_PROAUDIO_PLAYER=y" not in config
    assert "BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE=y" in config
    assert "BR2_PACKAGE_PROAUDIO_WEBUI=y" in config
    assert "# BR2_PACKAGE_PROAUDIO_NETWORKD is not set" in config
    assert "BR2_TOOLCHAIN_BUILDROOT_CXX=y" in config
    assert "BR2_INSTALL_LIBSTDCPP=y" not in config
    assert "board/common/rootfs-overlay" in config
    assert "board/qemu-aarch64/rootfs-overlay" in config
    assert "board/common/post-build-native.sh" in config


def test_qemu_inherits_common_runtime_and_mdns_policy():
    resolved = (
        ROOT
        / "br2-external/board/common/rootfs-overlay"
        / "etc/systemd/resolved.conf.d/10-proaudio.conf"
    ).read_text(encoding="utf-8")
    tmpfiles = (
        ROOT
        / "br2-external/package/proaudio-player-native/runtime"
        / "proaudio-player.tmpfiles.conf"
    ).read_text(encoding="utf-8")
    networkd_makefile = (
        ROOT
        / "br2-external/package/proaudio-networkd"
        / "proaudio-networkd.mk"
    ).read_text(encoding="utf-8")

    assert "MulticastDNS=no" in resolved
    assert "LLMNR=no" in resolved
    assert "10-proaudio-resolved.conf" not in networkd_makefile

    assert (
        "d /var/lib/proaudio-player-alert/mpd "
        "0750 proaudio-player proaudio-player -"
        in tmpfiles
    )
    assert (
        "d /var/lib/proaudio-player-alert/mpd/playlists "
        "0750 proaudio-player proaudio-player -"
        in tmpfiles
    )
    assert (
        "d /srv/music 0755 proaudio-player proaudio-player -"
        in tmpfiles
    )

    # MPD creates its own binary database. An empty placeholder is invalid.
    assert "/var/lib/proaudio-player-alert/mpd/database" not in tmpfiles


def test_qemu_virtual_output_is_external_to_native_core():
    helper = (
        QEMU_BOARD
        / "rootfs-overlay/usr/libexec/proaudio-player/qemu-virtual-audio"
    ).read_text(encoding="utf-8")
    unit = (
        QEMU_BOARD
        / "rootfs-overlay/usr/lib/systemd/system/proaudio-qemu-audio.service"
    ).read_text(encoding="utf-8")
    buses_dropin = (
        QEMU_BOARD
        / "rootfs-overlay/etc/systemd/system/proaudio-player-buses.service.d/qemu.conf"
    ).read_text(encoding="utf-8")

    assert "module-null-sink" in helper
    assert "qemu_virtual_dac" in helper
    assert "PULSE_SERVER=unix:/run/pulse/native" in unit
    assert "Before=proaudio-player-buses.service" in unit
    assert "Requires=proaudio-qemu-audio.service" in buses_dropin


def test_qemu_launcher_exposes_ui_and_supports_lan_tap_mode():
    launcher = (ROOT / "scripts/run-qemu.sh").read_text(encoding="utf-8")

    assert "qemu-system-aarch64" in launcher
    assert "-M virt" in launcher
    assert "-cpu cortex-a53" in launcher
    assert "QEMU_WEB_PORT" in launcher
    assert "hostfwd=tcp:127.0.0.1:${WEB_PORT}-:8080" in launcher
    assert "QEMU_NET_MODE" in launcher
    assert "QEMU_TAP_IF" in launcher
    assert "QEMU_SNAPSHOT" in launcher
    assert "$HOME/build/proaudio-qemu" in launcher
