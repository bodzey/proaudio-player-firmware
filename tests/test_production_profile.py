from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"
PROFILE = ROOT / "br2-external/configs/proaudio_rpi4_64_native_defconfig"
OVERLAY = BOARD / "rootfs-overlay"


def test_main_sources_track_main_branches():
    modules = (ROOT / ".gitmodules").read_text(encoding="utf-8")
    assert "path = sources/proaudio-player-native" in modules
    assert "path = sources/proaudio-player-webui" in modules
    assert modules.count("branch = main") == 2
    assert "branch = dev" not in modules


def test_rpi4_production_profile_has_no_local_login_or_dev_banner():
    defconfig = PROFILE.read_text(encoding="utf-8")
    assert 'BR2_TARGET_GENERIC_ISSUE="ProAudio Player"' in defconfig
    assert "# BR2_TARGET_ENABLE_ROOT_LOGIN is not set" in defconfig
    assert "# BR2_TARGET_GENERIC_GETTY is not set" in defconfig
    assert "linux-production.fragment" in defconfig
    assert "post-build-production.sh" in defconfig
    assert "NATIVE DEV" not in defconfig


def test_boot_has_no_video_serial_console_or_bluetooth():
    config = (BOARD / "config.txt").read_text(encoding="utf-8")
    cmdline = (BOARD / "cmdline.txt").read_text(encoding="utf-8")

    assert "camera_auto_detect=0" in config
    assert "display_auto_detect=0" in config
    assert "max_framebuffers=0" in config
    assert "enable_uart=0" in config
    assert "dtparam=audio=off" in config
    assert "dtoverlay=vc4-kms-v3d" in config
    assert "dtoverlay=disable-bt" in config
    assert "console=" not in cmdline
    assert "quiet" in cmdline
    assert "loglevel=3" in cmdline


def test_kernel_keeps_hdmi_audio_but_removes_local_ui_and_debug_classes():
    fragment = (BOARD / "linux-production.fragment").read_text(encoding="utf-8")

    for required in (
        "CONFIG_DRM_VC4=y",
        "CONFIG_SND_SOC_HDMI_CODEC=m",
        "CONFIG_SND_USB_AUDIO=y",
        "CONFIG_GPIO_CDEV=y",
        "CONFIG_BRCMFMAC=m",
    ):
        assert required in fragment

    for disabled in (
        "# CONFIG_DRM_V3D is not set",
        "# CONFIG_DRM_FBDEV_EMULATION is not set",
        "# CONFIG_FRAMEBUFFER_CONSOLE is not set",
        "# CONFIG_VT is not set",
        "# CONFIG_USB_HID is not set",
        "# CONFIG_USB_ACM is not set",
        "# CONFIG_USB_SERIAL is not set",
        "# CONFIG_USB_PRINTER is not set",
        "# CONFIG_MEDIA_SUPPORT is not set",
        "# CONFIG_BT is not set",
        "# CONFIG_DEBUG_FS is not set",
        "# CONFIG_FTRACE is not set",
        "# CONFIG_PROFILING is not set",
    ):
        assert disabled in fragment


def test_production_ssh_is_key_only_and_console_units_are_masked():
    sshd = (OVERLAY / "etc/ssh/sshd_config").read_text(encoding="utf-8")
    production = (BOARD / "post-build-production.sh").read_text(encoding="utf-8")

    assert "PermitRootLogin prohibit-password" in sshd
    assert "PubkeyAuthentication yes" in sshd
    assert "PasswordAuthentication no" in sshd
    assert "PermitEmptyPasswords no" in sshd
    assert "AuthenticationMethods publickey" in sshd
    assert "PROAUDIO_SSH_AUTHORIZED_KEYS_FILE" in production
    assert "authorized_keys" in production
    assert "debug-shell.service" in production
    assert "getty@tty1.service" in production
    assert "serial-getty@ttyAMA0.service" in production
