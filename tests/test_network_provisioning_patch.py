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


def test_dev_kernel_is_audio_appliance_profile():
    config = (BOARD / "config.txt").read_text(encoding="utf-8")
    fragment = (BOARD / "linux-headless-usb.fragment").read_text(encoding="utf-8")

    assert "dtoverlay=vc4-kms-v3d,cma-64" in config
    assert "cma-128" not in config
    assert "cma-512" not in config
    assert "camera_auto_detect=0" in config
    assert "display_auto_detect=0" in config
    assert "max_framebuffers=0" in config

    for setting in (
        "CONFIG_DRM=y",
        "CONFIG_DRM_VC4=y",
        "CONFIG_SND_USB_AUDIO=y",
        "CONFIG_SND_SOC=y",
        "CONFIG_SND_SOC_HDMI_CODEC=m",
        "CONFIG_SND_BCM2835_SOC_I2S=m",
        "CONFIG_SND_SIMPLE_CARD=m",
        "CONFIG_BRCMFMAC=m",
        "CONFIG_BRCMFMAC_SDIO=y",
        "CONFIG_EXT4_FS=y",
    ):
        assert setting in fragment

    for symbol in (
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
        "CONFIG_BCM2835_VCHIQ",
        "CONFIG_STAGING",
        "CONFIG_HID",
        "CONFIG_BT",
        "CONFIG_MD",
        "CONFIG_BLK_DEV_DM",
        "CONFIG_MTD",
        "CONFIG_IIO",
        "CONFIG_RTC_CLASS",
        "CONFIG_NETFILTER",
        "CONFIG_CAN",
        "CONFIG_NFC",
        "CONFIG_USB_GADGET",
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
