from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
QEMU_BOARD = ROOT / "br2-external/board/qemu-aarch64"


def test_qemu_profile_runs_current_native_and_webui_stack():
    config = (
        ROOT / "br2-external/configs/proaudio_qemu_aarch64_defconfig"
    ).read_text(encoding="utf-8")

    assert "# BR2_PACKAGE_PROAUDIO_PLAYER is not set" in config
    assert "BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE=y" in config
    assert "BR2_PACKAGE_PROAUDIO_WEBUI=y" in config
    assert "# BR2_PACKAGE_PROAUDIO_NETWORKD is not set" in config
    assert "board/common/rootfs-overlay" in config
    assert "board/qemu-aarch64/rootfs-overlay" in config
    assert "board/common/post-build-native.sh" in config


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
