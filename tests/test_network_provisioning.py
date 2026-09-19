from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "br2-external/package/proaudio-networkd"
NATIVE_PACKAGE = ROOT / "br2-external/package/proaudio-player-native"
BOARD = ROOT / "br2-external/board/raspberrypi4-64"
COMMON_POST_BUILD = ROOT / "br2-external/board/common/post-build-native.sh"


def test_networkd_is_a_rust_runtime_without_python_dependencies():
    config = (PACKAGE / "Config.in").read_text(encoding="utf-8")
    makefile = (PACKAGE / "proaudio-networkd.mk").read_text(encoding="utf-8")
    service = (PACKAGE / "proaudio-networkd.service").read_text(encoding="utf-8")
    cargo = (PACKAGE / "rust/Cargo.toml").read_text(encoding="utf-8")
    root_config = (ROOT / "br2-external/Config.in").read_text(encoding="utf-8")

    assert "BR2_PACKAGE_HOST_RUSTC_TARGET_ARCH_SUPPORTS" in config
    assert "select BR2_PACKAGE_LIBGPIOD" in config
    assert "select BR2_PACKAGE_LIBGPIOD_TOOLS" in config
    assert "BR2_PACKAGE_PYTHON" not in config
    assert "python" not in makefile.lower()
    assert "PROAUDIO_NETWORKD_SITE = $(PROAUDIO_NETWORKD_PKGDIR)/rust" in makefile
    assert "$(eval $(cargo-package))" in makefile
    assert 'name = "proaudio-networkd"' in cargo
    assert 'rust-version = "1.88"' in cargo
    assert "PYTHONUNBUFFERED" not in service
    assert "NoNewPrivileges=yes" in service

    assert not (PACKAGE / "proaudio-networkd").exists()
    assert not list(PACKAGE.glob("*.patch"))
    assert not (ROOT / "br2-external/package/proaudio-player/Config.in").exists()
    assert not (ROOT / "br2-external/package/proaudio-player/proaudio-player.mk").exists()
    assert 'package/proaudio-player/Config.in' not in root_config

    for name in ("proaudio_rpi4_64_defconfig", "proaudio_rpi4_64_native_defconfig"):
        defconfig = (ROOT / "br2-external/configs" / name).read_text(encoding="utf-8")
        assert "BR2_PACKAGE_PROAUDIO_PLAYER_NATIVE=y" in defconfig
        assert "BR2_PACKAGE_PROAUDIO_WEBUI=y" in defconfig
        assert "BR2_PACKAGE_PROAUDIO_NETWORKD=y" in defconfig
        assert "BR2_PACKAGE_PROAUDIO_PLAYER=y" not in defconfig
        assert "BR2_PACKAGE_PYTHON3" not in defconfig


def test_network_provisioning_contract_is_integrated_in_rust():
    network = (PACKAGE / "rust/src/network.rs").read_text(encoding="utf-8")
    portal = (PACKAGE / "rust/src/portal.rs").read_text(encoding="utf-8")
    main = (PACKAGE / "rust/src/main.rs").read_text(encoding="utf-8")
    gpio = (PACKAGE / "rust/src/gpio.rs").read_text(encoding="utf-8")

    assert '"--rescan",' in network
    assert '"auto",' in network
    assert "prepare_station_connection" in network
    assert '"rescan",' in network
    assert '"ssid",' in network
    assert 'args.extend_from_slice(&["hidden", "yes"])' in network
    assert "thread::sleep(Duration::from_millis(750))" in network
    assert "configure_hostname" in network
    assert 'format!("114,http://{}/", self.config.setup_address)' in network

    assert 'raw_path.split(\'?\')' in portal
    assert "content_length > 4096" in portal
    assert "header_bytes > 8192" in portal
    assert 'ControlMessage::Connect { ssid, password }' in portal

    assert "wifi_profile_exists()" in main
    assert "automatic provisioning is suppressed" in main
    assert "no saved Wi-Fi profile; starting initial Setup Mode" in main

    assert 'Command::new("/usr/bin/gpiomon")' in gpio
    assert '"pull-up"' in gpio
    assert '"%E"' in gpio
    assert "ControlMessage::Setup" in gpio


def test_dev_kernel_is_native_audio_appliance_profile():
    config = (BOARD / "config.txt").read_text(encoding="utf-8")
    fragment = (BOARD / "linux-headless-usb.fragment").read_text(encoding="utf-8")

    assert "dtoverlay=vc4-kms-v3d,cma-64" in config
    assert "cma-128" not in config
    assert "cma-512" not in config
    assert "camera_auto_detect=0" in config
    assert "display_auto_detect=0" in config
    assert "max_framebuffers=0" in config

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
        "CONFIG_BCM2835_VCHIQ",
        "CONFIG_STAGING",
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


def test_native_image_removes_unused_pulseaudio_policy_and_rejects_python():
    post_build = COMMON_POST_BUILD.read_text(encoding="utf-8")
    board_entry = (BOARD / "post-build-native.sh").read_text(encoding="utf-8")
    makefile = (NATIVE_PACKAGE / "proaudio-player-native.mk").read_text(
        encoding="utf-8"
    )

    assert "pulseaudio-system.conf" in post_build
    assert 'rm -f "$TARGET_DIR/etc/proaudio-player-alert/alerts-token"' in post_build
    assert "/etc/proaudio-player-alert/alerts-token" not in makefile
    assert "board/common/post-build-native.sh" in board_entry
    assert "Python runtime leaked into native target" in post_build
    assert '"$TARGET_DIR"/usr/bin/python[0-9]*' in post_build
    assert '"$TARGET_DIR"/usr/lib/python[0-9]*' in post_build
