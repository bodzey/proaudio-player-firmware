from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "br2-external/board/raspberrypi4-64"
CONFIGS = ROOT / "br2-external/configs"
NETWORK = ROOT / "br2-external/package/proaudio-networkd"
SHAIRPORT = ROOT / "br2-external/package/proaudio-shairport-sync"


def test_dev_kernel_is_audio_only_but_keeps_all_rpi_audio_outputs():
    fragment = (BOARD / "linux-headless-usb.fragment").read_text(encoding="utf-8")
    config = (BOARD / "config.txt").read_text(encoding="utf-8")
    cmdline = (BOARD / "cmdline.txt").read_text(encoding="utf-8")

    assert "CONFIG_DRM_VC4=y" in fragment
    assert "CONFIG_SND_SOC_HDMI_CODEC=m" in fragment
    assert "CONFIG_STAGING=y" in fragment
    assert "CONFIG_BCM_VIDEOCORE=y" in fragment
    assert "CONFIG_BCM2835_VCHIQ=y" in fragment
    assert "CONFIG_SND_BCM2835=m" in fragment
    for disabled in (
        "# CONFIG_DRM_V3D is not set",
        "# CONFIG_FB is not set",
        "# CONFIG_FRAMEBUFFER_CONSOLE is not set",
        "# CONFIG_VT is not set",
        "# CONFIG_MEDIA_SUPPORT is not set",
        "# CONFIG_STAGING_MEDIA is not set",
        "# CONFIG_VCHIQ_CDEV is not set",
        "# CONFIG_R8712U is not set",
        "# CONFIG_VT6656 is not set",
        "# CONFIG_FB_TFT is not set",
    ):
        assert disabled in fragment
    assert "camera_auto_detect=0" in config
    assert "display_auto_detect=0" in config
    assert "max_framebuffers=0" in config
    assert "dtparam=audio=on" in config
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


def test_native_rootfs_is_pure_pipewire_and_drops_unused_systemd_tools():
    defconfig = (CONFIGS / "proaudio_rpi4_64_native_defconfig").read_text(
        encoding="utf-8"
    )
    post_build = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")
    shairport_config = (SHAIRPORT / "Config.in").read_text(encoding="utf-8")
    shairport_makefile = (SHAIRPORT / "proaudio-shairport-sync.mk").read_text(
        encoding="utf-8"
    )

    for disabled in (
        "# BR2_PACKAGE_SYSTEMD_VCONSOLE is not set",
        "# BR2_PACKAGE_SYSTEMD_PSTORE is not set",
        "# BR2_PACKAGE_SYSTEMD_HOSTNAMED is not set",
        "# BR2_PACKAGE_ALSA_UTILS_ALSACTL is not set",
        "# BR2_PACKAGE_ALSA_UTILS_ALSAMIXER is not set",
    ):
        assert disabled in defconfig

    assert "BR2_PACKAGE_PULSEAUDIO=y" not in defconfig
    assert "BR2_PACKAGE_PULSEAUDIO" not in shairport_config
    assert "BR2_PACKAGE_PULSEAUDIO_HAS_ATOMIC" not in shairport_config
    assert "select BR2_PACKAGE_PIPEWIRE" in shairport_config
    assert "--without-pa" in shairport_makefile
    assert "--with-pw" in shairport_makefile

    for binary in (
        "pulseaudio",
        "pipewire-pulse",
        "pactl",
        "pacat",
        "parec",
        "paplay",
        "pamon",
    ):
        assert f'"$TARGET_DIR/usr/bin/{binary}"' in post_build
    assert '"$TARGET_DIR"/usr/lib/pulse-*/modules' in post_build
    assert "libpulse" in post_build
    assert "pw-record" in post_build
    assert "ERROR: libpulse reappeared" in post_build


def test_unique_hostname_patch_uses_same_device_identity_as_setup_ssid():
    patch = (NETWORK / "0002-set-unique-runtime-hostname.patch").read_text(
        encoding="utf-8"
    )
    makefile = (NETWORK / "proaudio-networkd.mk").read_text(encoding="utf-8")
    assert "self.device_serial_suffix()" in patch
    assert "proaudio-player-" in patch
    assert "self.configure_hostname()" in patch
    assert "0002-set-unique-runtime-hostname.patch" in makefile
