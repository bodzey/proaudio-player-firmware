from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"
CONFIGS = ROOT / "br2-external/configs"
NETWORK = ROOT / "br2-external/package/proaudio-networkd"


def test_dev_kernel_is_audio_only_but_keeps_hdmi_audio():
    fragment = (BOARD / "linux-headless-usb.fragment").read_text(encoding="utf-8")
    config = (BOARD / "config.txt").read_text(encoding="utf-8")
    cmdline = (BOARD / "cmdline.txt").read_text(encoding="utf-8")

    assert "CONFIG_DRM_VC4=y" in fragment
    assert "CONFIG_SND_SOC_HDMI_CODEC=m" in fragment
    for disabled in (
        "# CONFIG_DRM_V3D is not set",
        "# CONFIG_FB is not set",
        "# CONFIG_FRAMEBUFFER_CONSOLE is not set",
        "# CONFIG_VT is not set",
        "# CONFIG_MEDIA_SUPPORT is not set",
        "# CONFIG_SND_BCM2835 is not set",
    ):
        assert disabled in fragment
    assert "camera_auto_detect=0" in config
    assert "display_auto_detect=0" in config
    assert "max_framebuffers=0" in config
    assert "dtparam=audio=off" in config
    assert "console=tty1" not in cmdline
    assert "console=ttyAMA0,115200" in cmdline


def test_native_prune_fragment_blocks_bcm2711_residue():
    prune = (BOARD / "linux-native-prune.fragment").read_text(encoding="utf-8")
    defconfig = (CONFIGS / "proaudio_rpi4_64_native_defconfig").read_text(
        encoding="utf-8"
    )

    assert (
        "linux-headless-usb.fragment "
        "$(BR2_EXTERNAL_PROAUDIO_PATH)/board/raspberrypi4-64/"
        "linux-native-prune.fragment"
    ) in defconfig
    assert "CONFIG_NLS=y" in prune
    for disabled in (
        "# CONFIG_DLM is not set",
        "# CONFIG_IP_SCTP is not set",
        "# CONFIG_NLS_CODEPAGE_437 is not set",
        "# CONFIG_NLS_UTF8 is not set",
        "# CONFIG_XILLYUSB is not set",
        "# CONFIG_INET_DIAG is not set",
        "# CONFIG_TCP_CONG_ADVANCED is not set",
        "# CONFIG_XFRM_USER is not set",
        "# CONFIG_IKCONFIG is not set",
        "# CONFIG_DEBUG_FS is not set",
        "# CONFIG_PROFILING is not set",
        "# CONFIG_FTRACE is not set",
        "# CONFIG_NUMA is not set",
        "# CONFIG_COMPAT is not set",
        "# CONFIG_MODVERSIONS is not set",
        "# CONFIG_OF_CONFIGFS is not set",
        "# CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY is not set",
        "# CONFIG_SND_RPI_SIMPLE_SOUNDCARD is not set",
        "# CONFIG_SND_SOC_PCM5102A is not set",
        "# CONFIG_SND_SOC_PCM512x_I2C is not set",
        "# CONFIG_USB_EMI26 is not set",
    ):
        assert disabled in prune


def test_native_rootfs_drops_unused_systemd_and_pulseaudio_server():
    defconfig = (CONFIGS / "proaudio_rpi4_64_native_defconfig").read_text(
        encoding="utf-8"
    )
    post_build = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")

    for disabled in (
        "# BR2_PACKAGE_SYSTEMD_VCONSOLE is not set",
        "# BR2_PACKAGE_SYSTEMD_PSTORE is not set",
        "# BR2_PACKAGE_SYSTEMD_HOSTNAMED is not set",
    ):
        assert disabled in defconfig

    assert 'rm -f "$TARGET_DIR/usr/bin/pulseaudio"' in post_build
    assert '"$TARGET_DIR"/usr/lib/pulse-*/modules' in post_build
    assert "/usr/bin/pactl" not in post_build
    assert "libpulse" in post_build
    assert "pactl" in post_build


def test_unique_hostname_patch_uses_same_device_identity_as_setup_ssid():
    patch = (NETWORK / "0002-set-unique-runtime-hostname.patch").read_text(
        encoding="utf-8"
    )
    makefile = (NETWORK / "proaudio-networkd.mk").read_text(encoding="utf-8")
    assert "self.device_serial_suffix()" in patch
    assert "proaudio-player-" in patch
    assert "self.configure_hostname()" in patch
    assert "0002-set-unique-runtime-hostname.patch" in makefile
