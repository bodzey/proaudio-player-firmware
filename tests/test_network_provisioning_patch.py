from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "br2-external/package/proaudio-networkd"
NATIVE_PACKAGE = ROOT / "br2-external/package/proaudio-player-native"
BOARD = ROOT / "br2-external/board/raspberrypi4-64"


def test_network_patches_apply_in_build_order(tmp_path):
    source = PACKAGE / "proaudio-networkd"
    patch_files = sorted(PACKAGE.glob("*.patch"))
    makefile = (PACKAGE / "proaudio-networkd.mk").read_text(encoding="utf-8")
    work_source = tmp_path / "proaudio-networkd"
    work_source.write_bytes(source.read_bytes())

    assert patch_files
    for patch_file in patch_files:
        result = subprocess.run(
            ["patch", "--batch", "--forward", "-p1", "--directory", str(tmp_path)],
            input=patch_file.read_text(encoding="utf-8"),
            text=True,
            capture_output=True,
            check=False,
        )
        assert result.returncode == 0, (
            f"{patch_file.name} failed:\n{result.stdout}{result.stderr}"
        )

    patched = work_source.read_text(encoding="utf-8")
    assert "def _prepare_station_connection(self, ssid):" in patched
    assert '"device", "wifi", "rescan", "ifname", self.iface' in patched
    assert '"ssid", ssid' in patched
    assert 'args += ["hidden", "yes"]' in patched
    assert "visible = self._prepare_station_connection(ssid)" in patched
    assert "def configure_hostname(self):" in patched
    assert 'wanted = f"proaudio-player-{self.device_serial_suffix().lower()}"' in patched
    assert "self.configure_hostname()" in patched

    assert "PROAUDIO_NETWORKD_APPLY_LOCAL_PATCHES" in makefile
    assert "$(APPLY_PATCHES) $(@D) $(PROAUDIO_NETWORKD_PKGDIR)" in makefile
    assert (
        "PROAUDIO_NETWORKD_PRE_CONFIGURE_HOOKS += "
        "PROAUDIO_NETWORKD_APPLY_LOCAL_PATCHES"
    ) in makefile

    failure_tail = patched.split(
        'LOG.warning("Wi-Fi provisioning failed for %s: %s", ssid, error)', 1
    )[1].split("except Exception as exc:", 1)[0]
    assert "self.scan()" not in failure_tail
    assert "self.start_ap()" in failure_tail


def test_dev_kernel_is_native_audio_appliance_profile():
    config = (BOARD / "config.txt").read_text(encoding="utf-8")
    fragment = (BOARD / "linux-headless-usb.fragment").read_text(encoding="utf-8")

    assert "dtoverlay=vc4-kms-v3d,cma-64" in config
    assert "cma-128" not in config
    assert "cma-512" not in config
    assert "camera_auto_detect=0" in config
    assert "display_auto_detect=0" in config
    assert "max_framebuffers=0" in config
    assert "dtparam=audio=on" in config

    # Runtime contract derived from proaudio-player-native: onboard Ethernet and
    # Broadcom full-MAC Wi-Fi, IPv4 multicast discovery, GPIO setup control,
    # ext4 state/music, plus onboard analogue/HDMI/USB/I2S audio outputs.
    for setting in (
        "CONFIG_GPIOLIB=y",
        "CONFIG_GPIO_CDEV=y",
        "CONFIG_DUMMY=y",
        "CONFIG_IP_MULTICAST=y",
        "CONFIG_BCMGENET=y",
        "CONFIG_CFG80211=m",
        "CONFIG_BRCMFMAC=m",
        "CONFIG_BRCMFMAC_SDIO=y",
        "CONFIG_DRM=y",
        "CONFIG_DRM_VC4=y",
        "CONFIG_STAGING=y",
        "CONFIG_BCM_VIDEOCORE=y",
        "CONFIG_BCM2835_VCHIQ=y",
        "CONFIG_SND_BCM2835=m",
        "CONFIG_SND_USB_AUDIO=y",
        "CONFIG_SND_SOC=y",
        "CONFIG_SND_SOC_HDMI_CODEC=m",
        "CONFIG_SND_BCM2835_SOC_I2S=m",
        "CONFIG_SND_SIMPLE_CARD=m",
        "CONFIG_USB=y",
        "CONFIG_USB_XHCI_HCD=y",
        "CONFIG_EXT4_FS=y",
        "CONFIG_TMPFS=y",
    ):
        assert setting in fragment

    # Current native runtime has no video UI, Bluetooth, removable-drive mount
    # policy, alternate NIC/WLAN support, router stack or non-ext4 music store.
    # STAGING/VCHIQ are retained only for Raspberry Pi onboard analogue audio.
    for symbol in (
        "CONFIG_COMPILE_TEST",
        "CONFIG_DRM_V3D",
        "CONFIG_DRM_VC4_HDMI_CEC",
        "CONFIG_FB",
        "CONFIG_FRAMEBUFFER_CONSOLE",
        "CONFIG_VT",
        "CONFIG_MEDIA_SUPPORT",
        "CONFIG_RC_CORE",
        "CONFIG_STAGING_MEDIA",
        "CONFIG_VIDEO_BCM2835",
        "CONFIG_VIDEO_CODEC_BCM2835",
        "CONFIG_VIDEO_ISP_BCM2835",
        "CONFIG_VCHIQ_CDEV",
        "CONFIG_R8712U",
        "CONFIG_VT6656",
        "CONFIG_FB_TFT",
        "CONFIG_HID",
        "CONFIG_BT",
        "CONFIG_SND_SOC_ALL_CODECS",
        "CONFIG_MD",
        "CONFIG_BLK_DEV_DM",
        "CONFIG_MTD",
        "CONFIG_SCSI",
        "CONFIG_USB_STORAGE",
        "CONFIG_USB_UAS",
        "CONFIG_USB_DWCOTG",
        "CONFIG_USB_DWC2",
        "CONFIG_USB_DWC3",
        "CONFIG_USB_GADGET",
        "CONFIG_USB_NET_DRIVERS",
        "CONFIG_USB_SERIAL",
        "CONFIG_B43",
        "CONFIG_B43LEGACY",
        "CONFIG_WLAN_VENDOR_ATH",
        "CONFIG_WLAN_VENDOR_INTEL",
        "CONFIG_WLAN_VENDOR_INTERSIL",
        "CONFIG_WLAN_VENDOR_MARVELL",
        "CONFIG_WLAN_VENDOR_MEDIATEK",
        "CONFIG_WLAN_VENDOR_REALTEK",
        "CONFIG_QCA7000_SPI",
        "CONFIG_QCA7000_UART",
        "CONFIG_R8169",
        "CONFIG_MSE102X",
        "CONFIG_WIZNET_W5100",
        "CONFIG_NETFILTER",
        "CONFIG_NET_SCHED",
        "CONFIG_IP_SCTP",
        "CONFIG_CEPH_LIB",
        "CONFIG_NET_NSH",
        "CONFIG_MPLS",
        "CONFIG_BRIDGE",
        "CONFIG_VLAN_8021Q",
        "CONFIG_NET_DSA",
        "CONFIG_CAN",
        "CONFIG_NFC",
        "CONFIG_IIO",
        "CONFIG_RTC_CLASS",
        "CONFIG_MSDOS_FS",
        "CONFIG_VFAT_FS",
        "CONFIG_EXFAT_FS",
        "CONFIG_NTFS3_FS",
        "CONFIG_NLS",
        "CONFIG_NFS_FS",
        "CONFIG_CIFS",
    ):
        assert f"# {symbol} is not set" in fragment


def test_storage_does_not_seed_an_invalid_empty_mpd_database():
    script = (
        BOARD
        / "rootfs-overlay/usr/libexec/proaudio-player/prepare-storage"
    ).read_text(encoding="utf-8")
    assert "database_file=$data_mount/player-alert/mpd/database" in script
    assert 'rm -f "$database_file"' in script
    assert "for file in database state" not in script


def test_native_image_removes_unused_pulseaudio_system_policy_and_legacy_token():
    post_build = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")
    makefile = (NATIVE_PACKAGE / "proaudio-player-native.mk").read_text(
        encoding="utf-8"
    )
    assert "pulseaudio-system.conf" in post_build
    assert 'rm -f "$TARGET_DIR/etc/proaudio-player-alert/alerts-token"' in post_build
    assert "/etc/proaudio-player-alert/alerts-token" not in makefile
